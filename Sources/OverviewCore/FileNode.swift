import Foundation

/// One file or folder in a scanned tree.
///
/// Nodes are built by `DiskScanner` on background threads and are immutable
/// while a scan runs. Afterwards they are only mutated on the main thread
/// (see `removeFromParent`).
public final class FileNode: Identifiable, @unchecked Sendable {
    /// File name. For the scan root this is the full path that was scanned.
    public let name: String
    public let isDirectory: Bool

    /// Space taken on disk in bytes, including everything below a folder.
    public private(set) var size: Int64

    /// Number of files (not folders) in this subtree. 1 for a file.
    public private(set) var fileCount: Int

    /// Direct children, largest first. Always empty for files.
    public private(set) var children: [FileNode]

    public private(set) weak var parent: FileNode?

    /// True when the folder could not be read (permissions) or was skipped,
    /// so its size is incomplete.
    public let isUnreadable: Bool

    public init(file name: String, size: Int64) {
        self.name = name
        self.isDirectory = false
        self.size = size
        self.fileCount = 1
        self.children = []
        self.isUnreadable = false
    }

    public init(directory name: String, ownSize: Int64 = 0, children: [FileNode], isUnreadable: Bool = false) {
        self.name = name
        self.isDirectory = true
        self.isUnreadable = isUnreadable
        var total = ownSize
        var files = 0
        for child in children {
            total += child.size
            files += child.fileCount
        }
        self.size = total
        self.fileCount = files
        self.children = children.sorted(by: FileNode.largestFirst)
        for child in children {
            child.parent = self
        }
    }

    public var id: ObjectIdentifier { ObjectIdentifier(self) }

    static func largestFirst(_ a: FileNode, _ b: FileNode) -> Bool {
        if a.size != b.size { return a.size > b.size }
        return a.name < b.name
    }

    /// Absolute path of this node.
    public var path: String {
        guard let parent else { return name }
        var parts = [name]
        var node = parent
        while let next = node.parent {
            parts.append(node.name)
            node = next
        }
        // `node` is now the root, whose name is its full path.
        let base = node.name.hasSuffix("/") ? String(node.name.dropLast()) : node.name
        return base + "/" + parts.reversed().joined(separator: "/")
    }

    public var url: URL {
        URL(fileURLWithPath: path, isDirectory: isDirectory)
    }

    /// Name to show in the UI: the last path component for the root.
    public var displayName: String {
        guard parent == nil else { return name }
        if name == "/" { return "/" }
        return (name as NSString).lastPathComponent
    }

    /// The chain from the root down to this node, root first.
    public var ancestry: [FileNode] {
        var chain = [self]
        var node = self
        while let next = node.parent {
            chain.append(next)
            node = next
        }
        return chain.reversed()
    }

    public func isDescendant(of other: FileNode) -> Bool {
        var node = parent
        while let current = node {
            if current === other { return true }
            node = current.parent
        }
        return false
    }

    /// The ancestor of this node (or the node itself) that is a direct child
    /// of `ancestor`, or nil when this node is not below `ancestor`.
    public func child(under ancestor: FileNode) -> FileNode? {
        var node = self
        while let next = node.parent {
            if next === ancestor { return node }
            node = next
        }
        return nil
    }

    /// Detaches this node from the tree and subtracts its size from every
    /// ancestor. Used after a file was moved to the Trash.
    public func removeFromParent() {
        guard let parent else { return }
        parent.children.removeAll { $0 === self }
        var node: FileNode? = parent
        while let current = node {
            current.size -= size
            current.fileCount -= fileCount
            node = current.parent
        }
        // Sizes changed, so siblings higher up may need a new order.
        node = parent
        while let current = node {
            current.parent?.children.sort(by: FileNode.largestFirst)
            node = current.parent
        }
        self.parent = nil
    }

    /// The `limit` largest files in this subtree, largest first.
    public func largestFiles(limit: Int) -> [FileNode] {
        guard limit > 0 else { return [] }
        var best: [FileNode] = []
        var threshold: Int64 = -1

        func visit(_ node: FileNode) {
            // Children are sorted, so once one is too small the rest are too.
            for child in node.children {
                if best.count >= limit && child.size <= threshold { break }
                if child.isDirectory {
                    visit(child)
                } else {
                    best.append(child)
                    if best.count >= limit * 2 {
                        trim()
                    }
                }
            }
        }

        func trim() {
            best.sort(by: FileNode.largestFirst)
            if best.count > limit {
                best.removeSubrange(limit...)
            }
            if best.count >= limit, let last = best.last {
                threshold = last.size
            }
        }

        visit(self)
        trim()
        return best
    }
}
