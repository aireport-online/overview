import OverviewCore
import SwiftUI

/// Every file as a rectangle whose area is its size, nested by folder.
struct TreemapChart: View {
    @Environment(AppModel.self) private var model
    let focus: FileNode
    /// A new value makes the chart lay out and build up again.
    let revision: Int

    private struct BloomKey: Hashable {
        let focus: ObjectIdentifier
        let revision: Int
    }

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size).insetBy(dx: 2, dy: 2)
            let items = TreemapLayout.layout(root: focus, in: bounds)
            ZStack {
                TreemapBloom(items: items)
                    .id(BloomKey(focus: focus.id, revision: revision))
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

/// Plays the build-up of the treemap once: the tiles pop in one after another.
private struct TreemapBloom: View {
    let items: [TreemapItem]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress = 0.0

    var body: some View {
        TreemapTiles(items: items, progress: reduceMotion ? 1 : progress)
            .onAppear {
                withAnimation(.easeOut(duration: 0.8)) {
                    progress = 1
                }
            }
    }
}

private struct TreemapTiles: View, Animatable {
    let items: [TreemapItem]
    /// 0 is empty, 1 has every tile in place.
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private static let nameFont = Font.system(size: 11, weight: .semibold)
    private static let detailFont = Font.system(size: 10.5)
    private static let unbounded = CGSize(width: 4000, height: 40)
    /// The share of the animation over which the tiles start, first to last.
    private static let spread = 0.6

    var body: some View {
        Canvas { context, _ in
            let count = max(Double(items.count), 1)
            for (index, item) in items.enumerated() {
                let delay = Self.spread * Double(index) / count
                let linear = min(max((progress - delay) / (1 - Self.spread), 0), 1)
                guard linear > 0 else { continue }
                let arrival = 1 - pow(1 - linear, 3)

                // Tiles grow out of their own centre.
                let full = item.rect.insetBy(dx: 0.5, dy: 0.5)
                guard full.width > 0, full.height > 0 else { continue }
                let scale = CGFloat(0.55 + 0.45 * arrival)
                let rect = full.insetBy(dx: full.width * (1 - scale) / 2, dy: full.height * (1 - scale) / 2)

                var tile = context
                tile.opacity = min(linear * 2, 1)
                if item.isLeaf {
                    tile.fill(
                        Path(roundedRect: rect, cornerRadius: 2.5),
                        with: .linearGradient(
                            Palette.tile(branch: item.branch, depth: item.depth),
                            startPoint: rect.origin,
                            endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
                        )
                    )
                    guard arrival > 0.95 else { continue }
                    if rect.width >= 64 && rect.height >= 34 {
                        drawLabel(item.node.name, detail: Format.bytes(item.node.size), in: rect, context: tile)
                    } else if rect.width >= 48 && rect.height >= 18 {
                        drawLabel(item.node.name, detail: nil, in: rect, context: tile)
                    }
                } else {
                    tile.fill(
                        Path(roundedRect: rect, cornerRadius: 5),
                        with: .color(Palette.frame(branch: item.branch, depth: item.depth).opacity(0.88))
                    )
                    if item.hasHeader && arrival > 0.95 {
                        let header = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 17)
                        drawLabel(item.node.name, detail: nil, in: header, context: tile, trailing: Format.bytes(item.node.size))
                    }
                }
            }
        }
    }

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

/// Raises the tile under the pointer or selected in the list. Kept apart
/// from the tiles so that moving the pointer does not redraw them.
private struct TreemapHighlight: View {
    @Environment(AppModel.self) private var model
    let items: [TreemapItem]

    var body: some View {
        ZStack {
            if let target = model.hovered ?? model.selection, let item = visibleItem(for: target) {
                RaisedTile(rect: item.rect)
                    .id(target.id)
            }
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

private struct RaisedTile: View {
    let rect: CGRect

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var raised = false

    var body: some View {
        let lifted = raised || reduceMotion
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.white.opacity(0.16))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 2)
            )
            .shadow(color: Color.white.opacity(0.7), radius: lifted ? 10 : 0)
            .frame(width: max(rect.width, 1), height: max(rect.height, 1))
            .scaleEffect(lifted ? 1.03 : 0.94)
            .opacity(lifted ? 1 : 0)
            .position(x: rect.midX, y: rect.midY)
            .onAppear {
                withAnimation(.spring(duration: 0.35, bounce: 0.55)) {
                    raised = true
                }
            }
    }
}
