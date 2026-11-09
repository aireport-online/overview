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

    private static let nameFont = Font.system(size: 11, weight: .semibold)
    private static let detailFont = Font.system(size: 10.5)
    private static let unbounded = CGSize(width: 4000, height: 40)

    /// Draws a name, with optionally a size below it (`detail`) or at the
    /// right edge (`trailing`), inside `rect`.
    private func drawLabel(_ name: String, detail: String?, in rect: CGRect, context: GraphicsContext, trailing: String? = nil) {
        var context = context
        context.clip(to: Path(rect))

        var available = rect.width - 10
        if let trailing {
            let text = context.resolve(Text(trailing).font(Self.detailFont).foregroundColor(.white.opacity(0.75)))
            let width = text.measure(in: Self.unbounded).width
            if width + 60 < rect.width {
                context.draw(text, at: CGPoint(x: rect.maxX - 5, y: rect.minY + 2.5), anchor: .topTrailing)
                available -= width + 8
            }
        }
        if let text = fitted(name, font: Self.nameFont, color: .white, width: available, context: context) {
            context.draw(text, at: CGPoint(x: rect.minX + 5, y: rect.minY + 2), anchor: .topLeading)
        }
        if let detail, let text = fitted(detail, font: Self.detailFont, color: .white.opacity(0.8), width: rect.width - 10, context: context) {
            context.draw(text, at: CGPoint(x: rect.minX + 5, y: rect.minY + 17), anchor: .topLeading)
        }
    }

    /// `string` as text that fits in `width`, shortened with an ellipsis when
    /// needed. Nil when not even a couple of characters fit.
    private func fitted(_ string: String, font: Font, color: Color, width: CGFloat, context: GraphicsContext) -> GraphicsContext.ResolvedText? {
        var kept = string.count
        var candidate = string
        for _ in 0..<8 {
            let text = context.resolve(Text(candidate).font(font).foregroundColor(color))
            let measured = text.measure(in: Self.unbounded).width
            if measured <= width {
                return text
            }
            // Estimate how many characters fit, and try again.
            kept = min(Int(Double(kept) * Double(width / measured)), kept - 1)
            if kept < 2 {
                return nil
            }
            candidate = String(string.prefix(kept)) + "…"
        }
        return nil
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
