import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import OverviewCore

final class TreemapLayoutTests: XCTestCase {
    func testSquarifyFillsTheRectangleWithoutOverlap() {
        let rect = CGRect(x: 10, y: 20, width: 600, height: 400)
        let weights: [Double] = [6, 6, 4, 3, 2, 2, 1]
        let scale = Double(rect.width * rect.height) / weights.reduce(0, +)
        let areas = weights.map { $0 * scale }
        let rects = TreemapLayout.squarify(areas, in: rect)

        XCTAssertEqual(rects.count, areas.count)
        for (index, item) in rects.enumerated() {
            XCTAssertEqual(Double(item.width * item.height), areas[index], accuracy: 0.01)
            XCTAssertTrue(rect.insetBy(dx: -0.001, dy: -0.001).contains(item), "\(item) outside \(rect)")
            for other in rects[(index + 1)...] {
                let overlap = item.intersection(other)
                XCTAssertTrue(overlap.isNull || overlap.width * overlap.height < 0.001, "\(item) overlaps \(other)")
            }
        }
        // The classic example from the squarified treemap paper ends up with
        // reasonably square tiles.
        let worst = rects.map { max($0.width / $0.height, $0.height / $0.width) }.max() ?? 0
        XCTAssertLessThan(worst, 3.1)
    }

    func testSquarifyLeavesRoomWhenAreasAreSmallerThanTheRectangle() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let rects = TreemapLayout.squarify([2_500, 2_500], in: rect)
        let used = rects.reduce(0.0) { $0 + Double($1.width * $1.height) }
        XCTAssertEqual(used, 5_000, accuracy: 0.01)
        for item in rects {
            XCTAssertTrue(rect.contains(item))
        }
    }

    func testNestedLayout() {
        let big = FileNode(directory: "big", children: [
            FileNode(file: "one", size: 400),
            FileNode(file: "two", size: 200),
        ])
        let root = FileNode(directory: "/r", children: [
            big,
            FileNode(file: "solo", size: 300),
            FileNode(file: "speck", size: 0),
        ])
        let bounds = CGRect(x: 0, y: 0, width: 900, height: 600)
        let items = TreemapLayout.layout(root: root, in: bounds)

        XCTAssertEqual(items.map(\.node.name), ["big", "one", "two", "solo"])
        XCTAssertEqual(items.map(\.depth), [1, 2, 2, 1])
        XCTAssertEqual(items.map(\.branch), [0, 0, 0, 1])
        XCTAssertEqual(items.map(\.isLeaf), [false, true, true, true])
        XCTAssertTrue(items[0].hasHeader)

        // Children sit inside their folder, below the title strip.
        let folderRect = items[0].rect
        for child in items[1...2] {
            XCTAssertTrue(folderRect.contains(child.rect))
            XCTAssertGreaterThanOrEqual(child.rect.minY, folderRect.minY + 17 - 0.001)
        }
        // Top-level tiles are proportional to their sizes.
        let bigArea = Double(folderRect.width * folderRect.height)
        let soloArea = Double(items[3].rect.width * items[3].rect.height)
        XCTAssertEqual(bigArea / soloArea, 2.0, accuracy: 0.001)

        let hit = TreemapLayout.item(at: CGPoint(x: items[1].rect.midX, y: items[1].rect.midY), in: items)
        XCTAssertTrue(hit?.node === items[1].node)
        XCTAssertNil(TreemapLayout.item(at: CGPoint(x: -5, y: -5), in: items))
    }

    func testTinyItemsAreSkippedAndSmallFoldersBecomeLeaves() {
        var files = [FileNode(file: "huge", size: 1_000_000)]
        for index in 0..<5_000 {
            files.append(FileNode(file: "tiny\(index)", size: 1))
        }
        let nested = FileNode(directory: "small-folder", children: [FileNode(file: "x", size: 2_000)])
        files.append(nested)
        let root = FileNode(directory: "/r", children: files)
        let items = TreemapLayout.layout(root: root, in: CGRect(x: 0, y: 0, width: 800, height: 600))

        XCTAssertEqual(items.map(\.node.name), ["huge", "small-folder"])
        XCTAssertTrue(items[1].isLeaf, "a folder that is too small to subdivide is drawn as one tile")
    }

    func testEmptyInputs() {
        let empty = FileNode(directory: "/r", children: [])
        XCTAssertTrue(TreemapLayout.layout(root: empty, in: CGRect(x: 0, y: 0, width: 100, height: 100)).isEmpty)
        let root = FileNode(directory: "/r", children: [FileNode(file: "a", size: 10)])
        XCTAssertTrue(TreemapLayout.layout(root: root, in: .zero).isEmpty)
    }
}

final class SunburstLayoutTests: XCTestCase {
    private let fullCircle = 2 * Double.pi

    func testRingsAndAngles() {
        let media = FileNode(directory: "media", children: [
            FileNode(file: "movie", size: 300),
            FileNode(file: "song", size: 100),
        ])
        let root = FileNode(directory: "/r", children: [media, FileNode(file: "doc", size: 400)])
        let segments = SunburstLayout.layout(root: root)

        XCTAssertEqual(segments.map { $0.node?.name ?? "-" }, ["doc", "media", "movie", "song"])
        XCTAssertEqual(segments.map(\.ring), [0, 0, 1, 1])
        XCTAssertEqual(segments.map(\.branch), [0, 1, 1, 1])
        XCTAssertEqual(segments[0].start, 0, accuracy: 1e-9)
        XCTAssertEqual(segments[0].end, Double.pi, accuracy: 1e-9)
        XCTAssertEqual(segments[1].end, fullCircle, accuracy: 1e-9)
        // Children share the arc of their folder in proportion to their size.
        XCTAssertEqual(segments[2].start, Double.pi, accuracy: 1e-9)
        XCTAssertEqual(segments[2].end, Double.pi * 1.75, accuracy: 1e-9)
        XCTAssertEqual(segments[3].end, fullCircle, accuracy: 1e-9)
    }

    func testSmallItemsAreBundled() {
        var files = [FileNode(file: "big", size: 9_000)]
        for index in 0..<1_000 {
            files.append(FileNode(file: "s\(index)", size: 1))
        }
        let root = FileNode(directory: "/r", children: files)
        let segments = SunburstLayout.layout(root: root)

        XCTAssertEqual(segments.count, 2)
        XCTAssertNil(segments[1].node)
        XCTAssertEqual(segments[1].itemCount, 1_000)
        XCTAssertEqual(segments[1].size, 1_000)
        XCTAssertEqual(segments[1].start, segments[0].end, accuracy: 1e-9)
        XCTAssertEqual(segments[1].end, fullCircle, accuracy: 1e-9)
    }

    func testRingLimit() {
        var node = FileNode(file: "leaf", size: 10)
        for level in 0..<8 {
            node = FileNode(directory: "level\(level)", children: [node])
        }
        let segments = SunburstLayout.layout(root: node, rings: 3)
        XCTAssertEqual(segments.map(\.ring), [0, 1, 2])
    }

    func testGeometry() {
        let geometry = SunburstGeometry(center: CGPoint(x: 200, y: 200), outerRadius: 100, rings: 4, holeFraction: 0.2)
        XCTAssertEqual(geometry.holeRadius, 20)
        XCTAssertEqual(geometry.radii(ring: 0).inner, 20)
        XCTAssertEqual(geometry.radii(ring: 3).outer, 100, accuracy: 1e-9)

        XCTAssertEqual(geometry.locate(CGPoint(x: 205, y: 195)), .center)
        XCTAssertEqual(geometry.locate(CGPoint(x: 200, y: 50)), .outside)

        // Straight up is angle 0, to the right a quarter turn, clockwise.
        guard case let .ring(top, topAngle) = geometry.locate(CGPoint(x: 200, y: 170)) else { return XCTFail() }
        XCTAssertEqual(top, 0)
        XCTAssertEqual(topAngle, 0, accuracy: 1e-9)
        guard case let .ring(right, rightAngle) = geometry.locate(CGPoint(x: 295, y: 200)) else { return XCTFail() }
        XCTAssertEqual(right, 3)
        XCTAssertEqual(rightAngle, Double.pi / 2, accuracy: 1e-9)
        guard case let .ring(_, leftAngle) = geometry.locate(CGPoint(x: 150, y: 200)) else { return XCTFail() }
        XCTAssertEqual(leftAngle, Double.pi * 1.5, accuracy: 1e-9)

        // `point` is the inverse of `locate`.
        let point = geometry.point(angle: 1.0, radius: 70)
        guard case let .ring(ring, angle) = geometry.locate(point) else { return XCTFail() }
        XCTAssertEqual(ring, 2)
        XCTAssertEqual(angle, 1.0, accuracy: 1e-9)
    }

    func testHitTesting() {
        let root = FileNode(directory: "/r", children: [
            FileNode(file: "a", size: 300),
            FileNode(file: "b", size: 100),
        ])
        let segments = SunburstLayout.layout(root: root)
        let geometry = SunburstGeometry(center: .zero, outerRadius: 100, rings: 5)
        let inFirstRing = (geometry.radii(ring: 0).inner + geometry.radii(ring: 0).outer) / 2

        XCTAssertEqual(geometry.segment(at: geometry.point(angle: 1.0, radius: inFirstRing), in: segments)?.node?.name, "a")
        XCTAssertEqual(geometry.segment(at: geometry.point(angle: 5.5, radius: inFirstRing), in: segments)?.node?.name, "b")
        XCTAssertNil(geometry.segment(at: geometry.point(angle: 1.0, radius: 95), in: segments))
        XCTAssertNil(geometry.segment(at: .zero, in: segments))
    }
}
