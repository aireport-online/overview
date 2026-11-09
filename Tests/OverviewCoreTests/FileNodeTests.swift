import XCTest
@testable import OverviewCore

final class FileNodeTests: XCTestCase {
    private func sampleTree() -> FileNode {
        let docs = FileNode(directory: "docs", children: [
            FileNode(file: "a.txt", size: 100),
            FileNode(file: "b.txt", size: 300),
        ])
        let media = FileNode(directory: "media", children: [
            FileNode(file: "movie.mov", size: 5_000),
            FileNode(directory: "photos", children: [
                FileNode(file: "1.jpg", size: 700),
                FileNode(file: "2.jpg", size: 900),
            ]),
        ])
        return FileNode(directory: "/data/root", children: [docs, FileNode(file: "notes.md", size: 50), media])
    }

    func testSizesAndCountsRollUp() {
        let root = sampleTree()
        XCTAssertEqual(root.size, 7_050)
        XCTAssertEqual(root.fileCount, 6)
        XCTAssertEqual(root.children.map(\.name), ["media", "docs", "notes.md"])
        XCTAssertEqual(root.children[0].children.map(\.name), ["movie.mov", "photos"])
    }

    func testOwnSizeIsIncluded() {
        let folder = FileNode(directory: "x", ownSize: 4_096, children: [FileNode(file: "f", size: 10)])
        XCTAssertEqual(folder.size, 4_106)
    }

    func testPaths() {
        let root = sampleTree()
        let photo = root.children[0].children[1].children[0]
        XCTAssertEqual(photo.name, "2.jpg")
        XCTAssertEqual(photo.path, "/data/root/media/photos/2.jpg")
        XCTAssertEqual(root.path, "/data/root")
        XCTAssertEqual(root.displayName, "root")
        XCTAssertEqual(photo.ancestry.map(\.displayName), ["root", "media", "photos", "2.jpg"])

        let slash = FileNode(directory: "/", children: [FileNode(directory: "Users", children: [FileNode(file: "f", size: 1)])])
        XCTAssertEqual(slash.children[0].children[0].path, "/Users/f")
        XCTAssertEqual(slash.displayName, "/")
    }

    func testChildUnderAndDescendant() {
        let root = sampleTree()
        let media = root.children[0]
        let photo = media.children[1].children[0]
        XCTAssertTrue(photo.child(under: root) === media)
        XCTAssertTrue(media.child(under: root) === media)
        XCTAssertNil(root.child(under: media))
        XCTAssertTrue(photo.isDescendant(of: root))
        XCTAssertFalse(root.isDescendant(of: photo))
    }

    func testRemoveUpdatesAncestorsAndOrder() {
        let root = sampleTree()
        let media = root.children[0]
        let movie = media.children[0]
        movie.removeFromParent()

        XCTAssertNil(movie.parent)
        XCTAssertEqual(media.size, 1_600)
        XCTAssertEqual(media.fileCount, 2)
        XCTAssertEqual(root.size, 2_050)
        XCTAssertEqual(root.fileCount, 5)
        XCTAssertEqual(root.children.map(\.name), ["media", "docs", "notes.md"])

        media.children[0].removeFromParent()
        XCTAssertEqual(root.children.map(\.name), ["docs", "notes.md", "media"])
        XCTAssertEqual(root.size, 450)
    }

    func testLargestFiles() {
        let root = sampleTree()
        XCTAssertEqual(root.largestFiles(limit: 3).map(\.name), ["movie.mov", "2.jpg", "1.jpg"])
        XCTAssertEqual(root.largestFiles(limit: 100).count, 6)
        XCTAssertEqual(root.largestFiles(limit: 0).count, 0)
    }

    func testLargestFilesOnBigTree() {
        var folders: [FileNode] = []
        var sizes: [Int64] = []
        var seed: UInt64 = 42
        for folder in 0..<40 {
            var files: [FileNode] = []
            for file in 0..<60 {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let size = Int64(seed >> 40)
                sizes.append(size)
                files.append(FileNode(file: "f\(folder)-\(file)", size: size))
            }
            folders.append(FileNode(directory: "d\(folder)", children: files))
        }
        let root = FileNode(directory: "/r", children: folders)
        let expected = Array(sizes.sorted(by: >).prefix(25))
        XCTAssertEqual(root.largestFiles(limit: 25).map(\.size), expected)
    }
}
