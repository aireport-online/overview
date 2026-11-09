import Foundation

/// One rectangle of a treemap.
public struct TreemapItem {
    public let node: FileNode
    public let rect: CGRect
    /// 1 for direct children of the layout root.
    public let depth: Int
    /// Index of the top-level child this item belongs to; used for colouring.
    public let branch: Int
    /// True for tiles that are not subdivided further: files, and folders
    /// that are too small on screen to show their contents.
    public let isLeaf: Bool
    /// True when a title strip is reserved at the top of a folder.
    public let hasHeader: Bool
}

/// Nested squarified treemap (Bruls, Huizing, van Wijk).
public enum TreemapLayout {
    public struct Style {
        /// Height of the title strip on folders that are large enough.
        public var headerHeight: CGFloat = 17
        /// Smallest folder that gets a title strip.
        public var minHeaderSize = CGSize(width: 70, height: 44)
        /// Space between a folder's edge and its contents.
        public var padding: CGFloat = 2
        /// Tiles with a smaller area than this side squared are not drawn.
        public var minTileSide: CGFloat = 3
        /// Folders narrower or lower than this are drawn as a single tile.
        public var minSubdivideSide: CGFloat = 12

        public init() {}
    }

    /// Lays out everything below `root` inside `bounds`. Items are returned
    /// parents first, so the last item containing a point is the deepest one.
    public static func layout(root: FileNode, in bounds: CGRect, style: Style = Style()) -> [TreemapItem] {
        var items: [TreemapItem] = []
        place(childrenOf: root, in: bounds, depth: 1, branch: nil, style: style, into: &items)
        return items
    }

    /// The deepest item at `point`.
    public static func item(at point: CGPoint, in items: [TreemapItem]) -> TreemapItem? {
        items.last { $0.rect.contains(point) }
    }

    private static func place(
        childrenOf node: FileNode,
        in rect: CGRect,
        depth: Int,
        branch: Int?,
        style: Style,
        into items: inout [TreemapItem]
    ) {
        let area = Double(rect.width) * Double(rect.height)
        guard area > 0 else { return }
        var total: Int64 = 0
        for child in node.children {
            total += child.size
        }
        guard total > 0 else { return }

        // Children are sorted largest first, so the ones worth drawing form a
        // prefix. The space of the rest stays empty and shows the folder's own
        // colour, which reads as "lots of small things".
        let scale = area / Double(total)
        let minArea = Double(style.minTileSide * style.minTileSide)
        var areas: [Double] = []
        for child in node.children {
            let childArea = Double(child.size) * scale
            if childArea < minArea { break }
            areas.append(childArea)
        }
        guard !areas.isEmpty else { return }

        let rects = squarify(areas, in: rect)
        for (index, childRect) in rects.enumerated() {
            let child = node.children[index]
            let childBranch = branch ?? index
            let subdivide = child.isDirectory
                && !child.children.isEmpty
                && childRect.width >= style.minSubdivideSide
                && childRect.height >= style.minSubdivideSide

            guard subdivide else {
                items.append(TreemapItem(node: child, rect: childRect, depth: depth, branch: childBranch, isLeaf: true, hasHeader: false))
                continue
            }

            let hasHeader = childRect.width >= style.minHeaderSize.width && childRect.height >= style.minHeaderSize.height
            items.append(TreemapItem(node: child, rect: childRect, depth: depth, branch: childBranch, isLeaf: false, hasHeader: hasHeader))

            var inner = childRect.insetBy(dx: style.padding, dy: style.padding)
            if hasHeader {
                let cut = style.headerHeight - style.padding
                inner.origin.y += cut
                inner.size.height -= cut
            }
            if inner.width > 0 && inner.height > 0 {
                place(childrenOf: child, in: inner, depth: depth + 1, branch: childBranch, style: style, into: &items)
            }
        }
    }

    /// Splits `rect` into one rectangle per area, keeping them as square as
    /// possible. `areas` must be positive and should be sorted descending;
    /// their sum may be smaller than the area of `rect`, which leaves the
    /// remainder free.
    public static func squarify(_ areas: [Double], in rect: CGRect) -> [CGRect] {
        var result: [CGRect] = []
        result.reserveCapacity(areas.count)
        var free = rect
        var start = 0

        while start < areas.count {
            let side = Double(min(free.width, free.height))
            guard side > 0 else {
                // No room left (rounding): give the rest empty rectangles.
                for _ in start..<areas.count {
                    result.append(CGRect(origin: free.origin, size: .zero))
                }
                break
            }

            // Grow the row for as long as its worst aspect ratio improves.
            var sum = areas[start]
            var largest = areas[start]
            var smallest = areas[start]
            var worst = worstRatio(sum: sum, largest: largest, smallest: smallest, side: side)
            var end = start + 1
            while end < areas.count {
                let next = areas[end]
                let nextSum = sum + next
                let nextLargest = max(largest, next)
                let nextSmallest = min(smallest, next)
                let ratio = worstRatio(sum: nextSum, largest: nextLargest, smallest: nextSmallest, side: side)
                if ratio > worst { break }
                sum = nextSum
                largest = nextLargest
                smallest = nextSmallest
                worst = ratio
                end += 1
            }

            // The row runs along the shorter side of the free rectangle.
            if free.width >= free.height {
                let thickness = min(CGFloat(sum / side), free.width)
                var y = free.minY
                for index in start..<end {
                    let length = CGFloat(areas[index] / sum) * free.height
                    result.append(CGRect(x: free.minX, y: y, width: thickness, height: length))
                    y += length
                }
                free = CGRect(x: free.minX + thickness, y: free.minY, width: free.width - thickness, height: free.height)
            } else {
                let thickness = min(CGFloat(sum / side), free.height)
                var x = free.minX
                for index in start..<end {
                    let length = CGFloat(areas[index] / sum) * free.width
                    result.append(CGRect(x: x, y: free.minY, width: length, height: thickness))
                    x += length
                }
                free = CGRect(x: free.minX, y: free.minY + thickness, width: free.width, height: free.height - thickness)
            }
            start = end
        }
        return result
    }

    private static func worstRatio(sum: Double, largest: Double, smallest: Double, side: Double) -> Double {
        let sideSquared = side * side
        let sumSquared = sum * sum
        return max(sideSquared * largest / sumSquared, sumSquared / (sideSquared * smallest))
    }
}
