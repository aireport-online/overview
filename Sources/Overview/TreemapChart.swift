import OverviewCore
import SwiftUI

/// Every file as a rectangle whose area is its size, nested by folder.
struct TreemapChart: View {
    @Environment(AppModel.self) private var model
    let focus: FileNode
    /// Not read, but a new value makes the chart lay out again.
    let revision: Int

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size).insetBy(dx: 10, dy: 10)
            let items = TreemapLayout.layout(root: focus, in: bounds)
            ZStack {
                TreemapTiles(items: items)
                TreemapHighlight(items: items)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    model.hover(TreemapLayout.item(at: point, in: items)?.node)
                case .ended:
                    model.hover(nil)
                }
            }
            .gesture(
                SpatialTapGesture().onEnded { tap in
                    if let item = TreemapLayout.item(at: tap.location, in: items) {
                        model.activateInTreemap(item.node)
                    }
                }
            )
            .contextMenu {
                ChartMenu()
            }
        }
    }
}

private struct TreemapTiles: View {
    let items: [TreemapItem]

    var body: some View {
        Canvas { context, _ in
            for item in items {
                let rect = item.rect.insetBy(dx: 0.5, dy: 0.5)
                guard rect.width > 0, rect.height > 0 else { continue }

                if item.isLeaf {
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 1.5),
                        with: .linearGradient(
                            Palette.tile(branch: item.branch, depth: item.depth),
                            startPoint: rect.origin,
                            endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
                        )
                    )
                    if rect.width >= 64 && rect.height >= 34 {
                        drawLabel(item.node.name, detail: Format.bytes(item.node.size), in: rect, context: context)
                    } else if rect.width >= 48 && rect.height >= 18 {
                        drawLabel(item.node.name, detail: nil, in: rect, context: context)
                    }
                } else {
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 3),
                        with: .color(Palette.frame(branch: item.branch, depth: item.depth))
                    )
                    if item.hasHeader {
                        let header = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 17)
                        drawLabel(item.node.name, detail: nil, in: header, context: context, trailing: Format.bytes(item.node.size))
                    }
                }
            }
        }
    }

    /// Draws a name (and optionally a size below or to the right of it),
    /// clipped to `rect`.
    private func drawLabel(_ name: String, detail: String?, in rect: CGRect, context: GraphicsContext, trailing: String? = nil) {
        var clipped = context
        clipped.clip(to: Path(rect.insetBy(dx: 3, dy: 0)))

        var nameWidth = rect.width - 10
        if let trailing {
            let text = clipped.resolve(
                Text(trailing).font(.system(size: 10.5)).foregroundColor(.white.opacity(0.75))
            )
            let size = text.measure(in: CGSize(width: 400, height: 20))
            if size.width + 60 < rect.width {
                clipped.draw(text, at: CGPoint(x: rect.maxX - 5, y: rect.minY + 2.5), anchor: .topTrailing)
                nameWidth -= size.width + 8
            }
        }

        var nameContext = clipped
        nameContext.clip(to: Path(CGRect(x: rect.minX, y: rect.minY, width: max(nameWidth + 5, 0), height: rect.height)))
        nameContext.draw(
            Text(name).font(.system(size: 11, weight: .semibold)).foregroundColor(.white),
            at: CGPoint(x: rect.minX + 5, y: rect.minY + 2),
            anchor: .topLeading
        )
        if let detail {
            clipped.draw(
                Text(detail).font(.system(size: 10.5)).foregroundColor(.white.opacity(0.8)),
                at: CGPoint(x: rect.minX + 5, y: rect.minY + 17),
                anchor: .topLeading
            )
        }
    }
}

/// Outlines the item under the pointer or selected in the list. Kept apart
/// from the tiles so that moving the pointer does not redraw them.
private struct TreemapHighlight: View {
    @Environment(AppModel.self) private var model
    let items: [TreemapItem]

    var body: some View {
        let target = model.hovered ?? model.selection
        Canvas { context, _ in
            guard let target, let item = visibleItem(for: target) else { return }
            let path = Path(roundedRect: item.rect.insetBy(dx: 1.5, dy: 1.5), cornerRadius: 2)
            context.fill(path, with: .color(.white.opacity(0.16)))
            context.stroke(path, with: .color(.white), lineWidth: 2)
        }
        .allowsHitTesting(false)
    }

    /// The tile of `node`, or of the nearest folder above it that is drawn.
    private func visibleItem(for node: FileNode) -> TreemapItem? {
        var current: FileNode? = node
        while let candidate = current {
            if let item = items.last(where: { $0.node === candidate }) {
                return item
            }
            current = candidate.parent
        }
        return nil
    }
}
