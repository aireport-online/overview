import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum ScanError: Error, Equatable {
    case notFound(String)
    case notADirectory(String)
}

/// Live counters of a running scan. Safe to read from any thread.
public final class ScanProgress: @unchecked Sendable {
    public struct Snapshot: Sendable, Equatable {
        public var files = 0
        public var folders = 0
        public var bytes: Int64 = 0
        public var unreadableFolders = 0
        public var currentPath = ""

        public init() {}
    }

    private let lock = NSLock()
    private var state = Snapshot()
    private var unreadable: [String] = []
    private static let unreadableLimit = 200

    public var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    /// The first folders that could not be read (capped).
    public var unreadablePaths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return unreadable
    }

    func addFolder(path: String, files: Int, bytes: Int64) {
        lock.lock()
        state.folders += 1
        state.files += files
        state.bytes += bytes
        state.currentPath = path
        lock.unlock()
    }

    func addUnreadable(path: String) {
        lock.lock()
        state.unreadableFolders += 1
        if unreadable.count < Self.unreadableLimit {
            unreadable.append(path)
        }
        lock.unlock()
    }
}

/// Walks a folder and builds a `FileNode` tree with the space each item takes
/// on disk (allocated blocks, like `du`), scanning subfolders in parallel.
public final class DiskScanner: @unchecked Sendable {
    public let progress = ScanProgress()

    private let mountPoints: Set<String>
    private let linkLock = NSLock()
    private var seenLinks = Set<FileID>()

    private struct FileID: Hashable {
        let device: UInt64
        let inode: UInt64
    }

    private struct Subfolder {
        let name: String
        let ownSize: Int64
    }

    private struct Listing {
        var files: [FileNode] = []
        var subfolders: [Subfolder] = []
        var bytes: Int64 = 0
    }

    /// - Parameter mountPoints: folders that are skipped because another
    ///   volume is mounted there.
    public init(mountPoints: Set<String> = MountPoints.current()) {
        self.mountPoints = mountPoints
    }

    /// Scans `path`. Throws `CancellationError` when the surrounding task is
    /// cancelled.
    public func scan(path: String) async throws -> FileNode {
        guard let resolved = realpath(path, nil) else {
            throw ScanError.notFound(path)
        }
        let root = String(cString: resolved)
        free(resolved)

        var info = stat()
        guard lstat(root, &info) == 0 else {
            throw ScanError.notFound(path)
        }
        guard (info.st_mode & S_IFMT) == S_IFDIR else {
            throw ScanError.notADirectory(path)
        }

        let node = await scanFolder(path: root, name: root, ownSize: Self.allocatedSize(info))
        try Task.checkCancellation()
        return node
    }

    private func scanFolder(path: String, name: String, ownSize: Int64) async -> FileNode {
        if Task.isCancelled {
            return FileNode(directory: name, ownSize: ownSize, children: [])
        }
        guard let listing = readFolder(path) else {
            progress.addUnreadable(path: path)
            return FileNode(directory: name, ownSize: ownSize, children: [], isUnreadable: true)
        }
        progress.addFolder(path: path, files: listing.files.count, bytes: listing.bytes + ownSize)

        var children = listing.files
        let prefix = path == "/" ? "/" : path + "/"
        let subfolders = listing.subfolders

        if subfolders.count == 1 {
            let only = subfolders[0]
            children.append(await scanFolder(path: prefix + only.name, name: only.name, ownSize: only.ownSize))
        } else if !subfolders.isEmpty {
            await withTaskGroup(of: FileNode.self) { group in
                for subfolder in subfolders {
                    group.addTask {
                        await self.scanFolder(path: prefix + subfolder.name, name: subfolder.name, ownSize: subfolder.ownSize)
                    }
                }
                for await child in group {
                    children.append(child)
                }
            }
        }
        return FileNode(directory: name, ownSize: ownSize, children: children)
    }

    /// Reads one folder without recursing. Returns nil when it cannot be opened.
    private func readFolder(_ path: String) -> Listing? {
        guard let stream = opendir(path) else { return nil }
        defer { closedir(stream) }
        let descriptor = dirfd(stream)
        let prefix = path == "/" ? "/" : path + "/"
        var listing = Listing()

        while let entry = readdir(stream) {
            let capacity = MemoryLayout.size(ofValue: entry.pointee.d_name)
            withUnsafePointer(to: &entry.pointee.d_name) { tuple in
                tuple.withMemoryRebound(to: CChar.self, capacity: capacity) { cName in
                    // Skip "." and "..".
                    if cName[0] == 46 && (cName[1] == 0 || (cName[1] == 46 && cName[2] == 0)) {
                        return
                    }
                    var info = stat()
                    guard fstatat(descriptor, cName, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
                        return
                    }
                    let name = String(cString: cName)
                    let size = Self.allocatedSize(info)
                    let type = info.st_mode & S_IFMT

                    if type == S_IFDIR {
                        if mountPoints.contains(prefix + name) {
                            return
                        }
                        if Self.isCloudPlaceholder(info) {
                            // Listing it would make the system download its
                            // contents; it takes no space locally anyway.
                            listing.files.append(FileNode(directory: name, ownSize: size, children: []))
                            listing.bytes += size
                            return
                        }
                        listing.subfolders.append(Subfolder(name: name, ownSize: size))
                    } else {
                        var counted = size
                        if type == S_IFREG && info.st_nlink > 1 && !isFirstLink(info) {
                            // Hard links share their blocks: count them once.
                            counted = 0
                        }
                        listing.files.append(FileNode(file: name, size: counted))
                        listing.bytes += counted
                    }
                }
            }
        }
        return listing
    }

    private func isFirstLink(_ info: stat) -> Bool {
        let id = FileID(device: UInt64(truncatingIfNeeded: info.st_dev), inode: UInt64(truncatingIfNeeded: info.st_ino))
        linkLock.lock()
        defer { linkLock.unlock() }
        return seenLinks.insert(id).inserted
    }

    private static func allocatedSize(_ info: stat) -> Int64 {
        // st_blocks is always in 512-byte units, whatever the block size.
        Int64(info.st_blocks) * 512
    }

    private static func isCloudPlaceholder(_ info: stat) -> Bool {
        #if canImport(Darwin)
        let dataless: UInt32 = 0x4000_0000 // SF_DATALESS
        return (info.st_flags & dataless) != 0
        #else
        return false
        #endif
    }
}
