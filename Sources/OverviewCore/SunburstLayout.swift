import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// One arc of a sunburst chart. Angles are in radians, 0 at twelve o'clock,
/// increasing clockwise, in the range 0...2π.
public struct SunburstSegment {
    /// The item this arc stands for, or nil when it bundles the items of
    /// `parent` that are too small to draw on their own.
    public let node: FileNode?
    public let parent: FileNode
    /// 0 for the innermost ring (direct children of the layout root).
    public let ring: Int
    public let start: Double
    public let end: Double
    /// Index of the top-level child this arc belongs to; used for colouring.
    public let branch: Int
    public let size: Int64
    /// Number of items bundled in this arc (1 for a regular arc).
    public let itemCount: Int
}

public enum SunburstLayout {
    /// - Parameters:
    ///   - rings: how many levels below `root` are shown.
    ///   - minAngle: arcs narrower than this are bundled into one grey arc.
    public static func layout(root: FileNode, rings: Int = 5, minAngle: Double = 0.012) -> [SunburstSegment] {
        var segments: [SunburstSegment] = []
        guard rings > 0 else { return segments }
        place(childrenOf: root, start: 0, end: 2 * Double.pi, ring: 0, branch: nil, rings: rings, minAngle: minAngle, into: &segments)
        return segments
    }

    private static func place(
        childrenOf node: FileNode,
        start: Double,
        end: Double,
        ring: Int,
        branch: Int?,
        rings: Int,
        minAngle: Double,
        into segments: inout [SunburstSegment]
    ) {
        var total: Int64 = 0
        for child in node.children {
            total += child.size
        }
        guard total > 0 else { return }
        let span = end - start
        var cursor = start
        var placed: Int64 = 0

        for (index, child) in node.children.enumerated() {
            let angle = span * Double(child.size) / Double(total)
            if angle < minAngle {
                // Sorted largest first: everything from here on is too small.
                let rest = total - placed
                if rest > 0 && end - cursor >= minAngle / 4 {
                    segments.append(SunburstSegment(
                        node: nil, parent: node, ring: ring, start: cursor, end: end,
                        branch: branch ?? index, size: rest, itemCount: node.children.count - index
                    ))
                }
                return
            }
            let childEnd = min(cursor + angle, end)
            let childBranch = branch ?? index
            segments.append(SunburstSegment(
                node: child, parent: node, ring: ring, start: cursor, end: childEnd,
                branch: childBranch, size: child.size, itemCount: 1
            ))
            if child.isDirectory && ring + 1 < rings {
                place(childrenOf: child, start: cursor, end: childEnd, ring: ring + 1, branch: childBranch, rings: rings, minAngle: minAngle, into: &segments)
            }
            cursor = childEnd
            placed += child.size
        }
    }
}

/// Maps between screen points and the rings and angles of a sunburst.
public struct SunburstGeometry {
    public enum Location: Equatable {
        case outside
        /// The disc in the middle, which stands for the layout root.
        case center
        case ring(Int, angle: Double)
    }

    public let center: CGPoint
    public let outerRadius: CGFloat
    public let rings: Int
    /// Radius of the middle disc as a fraction of `outerRadius`.
    public let holeFraction: CGFloat

    public init(center: CGPoint, outerRadius: CGFloat, rings: Int, holeFraction: CGFloat = 0.26) {
        self.center = center
        self.outerRadius = outerRadius
        self.rings = max(rings, 1)
        self.holeFraction = holeFraction
    }

    public var holeRadius: CGFloat { outerRadius * holeFraction }

    private var ringThickness: CGFloat { (outerRadius - holeRadius) / CGFloat(rings) }

    public func radii(ring: Int) -> (inner: CGFloat, outer: CGFloat) {
        let inner = holeRadius + CGFloat(ring) * ringThickness
        return (inner, inner + ringThickness)
    }

    public func locate(_ point: CGPoint) -> Location {
        let dx = Double(point.x - center.x)
        let dy = Double(point.y - center.y)
        let distance = CGFloat((dx * dx + dy * dy).squareRoot())
        if distance < holeRadius { return .center }
        guard distance < outerRadius, ringThickness > 0 else { return .outside }
        let ring = min(Int((distance - holeRadius) / ringThickness), rings - 1)
        var angle = atan2(dx, -dy)
        if angle < 0 { angle += 2 * Double.pi }
        return .ring(ring, angle: angle)
    }

    public func segment(at point: CGPoint, in segments: [SunburstSegment]) -> SunburstSegment? {
        guard case let .ring(ring, angle) = locate(point) else { return nil }
        return segments.first { $0.ring == ring && angle >= $0.start && angle < $0.end }
    }

    /// The point at `angle` on the circle with `radius`.
    public func point(angle: Double, radius: CGFloat) -> CGPoint {
        CGPoint(x: center.x + radius * CGFloat(sin(angle)), y: center.y - radius * CGFloat(cos(angle)))
    }
}
