import XCTest
@testable import OverviewCore

final class DiskScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        // Resolve symlinks (/var -> /private/var on macOS) so paths compare equal.
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        root = base.appendingPathComponent("overview-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        _ = chmod(root.appendingPathComponent("locked").path, 0o755)
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ relativePath: String, bytes: Int) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x5A, count: bytes).write(to: url)
    }

    /// What `du` reports for a path, in bytes.
    private func diskUsage(_ path: String) throws -> Int64 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        let kilobytes = Int64(output.split(whereSeparator: { $0 == "\t" || $0 == " " }).first ?? "") ?? -1
        return kilobytes * 1024
    }

    func testScanBuildsTheTree() async throws {
        try write("a/big.bin", bytes: 300_000)
        try write("a/small.txt", bytes: 10)
        try write("a/deep/er/file.dat", bytes: 50_000)
        try write("b/medium.bin", bytes: 120_000)
        try write("top.txt", bytes: 5_000)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("empty"), withIntermediateDirectories: true)

        let scanner = DiskScanner(mountPoints: [])
        let tree = try await scanner.scan(path: root.path)

        XCTAssertEqual(tree.path, root.path)
        XCTAssertTrue(tree.isDirectory)
        XCTAssertEqual(tree.fileCount, 5)
        XCTAssertEqual(Set(tree.children.map(\.name)), ["a", "b", "top.txt", "empty"])
        XCTAssertEqual(tree.children.first?.name, "a")

        let a = try XCTUnwrap(tree.children.first { $0.name == "a" })
        XCTAssertEqual(a.children.first?.name, "big.bin")
        let file = try XCTUnwrap(a.children.first { $0.name == "deep" }?.children.first?.children.first)
        XCTAssertEqual(file.path, root.path + "/a/deep/er/file.dat")
        XCTAssertGreaterThanOrEqual(file.size, 50_000)
        XCTAssertLessThan(file.size, 50_000 + 64 * 1024)

        // Same accounting as du: allocated blocks, folders included.
        XCTAssertEqual(tree.size, try diskUsage(root.path))

        let progress = scanner.progress.snapshot
        XCTAssertEqual(progress.files, 5)
        XCTAssertEqual(progress.folders, 6)
        XCTAssertEqual(progress.bytes, tree.size)
        XCTAssertEqual(progress.unreadableFolders, 0)
    }

    func testHardLinksAreCountedOnce() async throws {
        try write("original.bin", bytes: 200_000)
        try FileManager.default.linkItem(
            at: root.appendingPathComponent("original.bin"),
            to: root.appendingPathComponent("link.bin")
        )
        let tree = try await DiskScanner(mountPoints: []).scan(path: root.path)
        XCTAssertEqual(tree.fileCount, 2)
        XCTAssertEqual(tree.size, try diskUsage(root.path))
        XCTAssertEqual(tree.children.filter { $0.size > 0 }.count, 1)
    }

    func testSymlinksAreNotFollowed() async throws {
        try write("target/data.bin", bytes: 100_000)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("shortcut"),
            withDestinationURL: root.appendingPathComponent("target")
        )
        let tree = try await DiskScanner(mountPoints: []).scan(path: root.path)
        let shortcut = try XCTUnwrap(tree.children.first { $0.name == "shortcut" })
        XCTAssertFalse(shortcut.isDirectory)
        XCTAssertLessThan(shortcut.size, 8_192)
        XCTAssertEqual(tree.fileCount, 2)
    }

    func testMountPointsAreSkipped() async throws {
        try write("keep/a.bin", bytes: 10_000)
        try write("other-volume/b.bin", bytes: 10_000)
        let scanner = DiskScanner(mountPoints: [root.path + "/other-volume"])
        let tree = try await scanner.scan(path: root.path)
        XCTAssertEqual(tree.children.map(\.name), ["keep"])

        // The folder you ask for is always scanned, mount point or not.
        let direct = try await scanner.scan(path: root.path + "/other-volume")
        XCTAssertEqual(direct.fileCount, 1)
    }

    func testUnreadableFoldersAreReported() async throws {
        try XCTSkipIf(getuid() == 0, "root can read everything")
        try write("locked/secret.bin", bytes: 10_000)
        try write("open/a.bin", bytes: 10_000)
        XCTAssertEqual(chmod(root.appendingPathComponent("locked").path, 0o000), 0)

        let scanner = DiskScanner(mountPoints: [])
        let tree = try await scanner.scan(path: root.path)
        let locked = try XCTUnwrap(tree.children.first { $0.name == "locked" })
        XCTAssertTrue(locked.isUnreadable)
        XCTAssertTrue(locked.children.isEmpty)
        XCTAssertEqual(scanner.progress.snapshot.unreadableFolders, 1)
        XCTAssertEqual(scanner.progress.unreadablePaths, [root.path + "/locked"])
    }

    func testErrors() async throws {
        try write("file.txt", bytes: 10)
        let scanner = DiskScanner(mountPoints: [])
        do {
            _ = try await scanner.scan(path: root.path + "/missing")
            XCTFail("expected an error")
        } catch let error as ScanError {
            XCTAssertEqual(error, .notFound(root.path + "/missing"))
        }
        do {
            _ = try await scanner.scan(path: root.path + "/file.txt")
            XCTFail("expected an error")
        } catch let error as ScanError {
            XCTAssertEqual(error, .notADirectory(root.path + "/file.txt"))
        }
    }

    func testCancellation() async throws {
        for folder in 0..<30 {
            for file in 0..<20 {
                try write("d\(folder)/sub/f\(file)", bytes: 1)
            }
        }
        let path = root.path
        let task = Task { try await DiskScanner(mountPoints: []).scan(path: path) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testMountTableEscapes() {
        XCTAssertEqual(MountPoints.unescape("/mnt/My\\040Disk"), "/mnt/My Disk")
        XCTAssertEqual(MountPoints.unescape("/plain"), "/plain")
        XCTAssertFalse(MountPoints.current().contains("/"))
    }
}
