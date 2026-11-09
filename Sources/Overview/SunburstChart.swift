import OverviewCore
import SwiftUI

/// The folder on screen as a disc, with a ring for every level below it.
struct SunburstChart: View {
    @Environment(AppModel.self) private var model
    let focus: FileNode
    /// Not read, but a new value makes the chart lay out again.
    let revision: Int

    private static let rings = 5

    var body: some View {
        GeometryReader { proxy in
            let geometry = SunburstGeometry(
                center: CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2),
                outerRadius: max(min(proxy.size.width, proxy.size.height) / 2 - 18, 40),
                rings: Self.rings
            )
            let segments = SunburstLayout.layout(root: focus, rings: Self.rings)
            ZStack {
                SunburstArcs(segments: segments, geometry: geometry)
                SunburstHighlight(segments: segments, geometry: geometry)
                SunburstCenter(focus: focus, diameter: geometry.holeRadius * 2)
                    .position(geometry.center)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    if let segment = geometry.segment(at: point, in: segments) {
                        model.hover(segment.node ?? segment.parent)
                    } else {
                        model.hover(nil)
                    }
                case .ended:
                    model.hover(nil)
                }
            }
            .gesture(
                SpatialTapGesture().onEnded { tap in
                    if geometry.locate(tap.location) == .center {
                        model.goUp()
                    } else if let segment = geometry.segment(at: tap.location, in: segments) {
                        model.activateInSunburst(segment.node ?? segment.parent)
                    }
                }
            )
            .contextMenu {
                ChartMenu()
            }
        }
    }
}

extension SunburstGeometry {
    /// The outline of an arc. Built from points rather than `addArc`, so it
    /// uses exactly the angles that hit-testing uses.
    func path(for segment: SunburstSegment, inset: CGFloat = 0) -> Path {
        let band = radii(ring: segment.ring)
        let inner = band.inner + inset
        let outer = band.outer - inset
        let span = segment.end - segment.start
        let steps = max(Int((span / (Double.pi / 120)).rounded(.up)), 1)
        var path = Path()
        for step in 0...steps {
            let angle = segment.start + span * Double(step) / Double(steps)
            let corner = point(angle: angle, radius: outer)
            if step == 0 {
                path.move(to: corner)
            } else {
                path.addLine(to: corner)
            }
        }
        for step in (0...steps).reversed() {
            let angle = segment.start + span * Double(step) / Double(steps)
            path.addLine(to: point(angle: angle, radius: inner))
        }
        path.closeSubpath()
        return path
    }
}

private struct SunburstArcs: View {
    let segments: [SunburstSegment]
    let geometry: SunburstGeometry

    var body: some View {
        Canvas { context, _ in
            let separator = Color(nsColor: .windowBackgroundColor)
            for segment in segments {
                let path = geometry.path(for: segment)
                let color: Color
                if let node = segment.node {
                    color = Palette.arc(branch: segment.branch, ring: segment.ring, isDirectory: node.isDirectory)
                } else {
                    color = Palette.bundled
                }
                context.fill(path, with: .color(color))
                context.stroke(path, with: .color(separator), lineWidth: 1)
            }
        }
    }
}

/// Lights up the arc under the pointer or selected in the list. Kept apart
/// from the arcs so that moving the pointer does not redraw them.
private struct SunburstHighlight: View {
    @Environment(AppModel.self) private var model
    let segments: [SunburstSegment]
    let geometry: SunburstGeometry

    var body: some View {
        let target = model.hovered ?? model.selection
        Canvas { context, _ in
            guard let target, let segment = visibleSegment(for: target) else { return }
            let path = geometry.path(for: segment, inset: 1)
            context.fill(path, with: .color(.white.opacity(0.28)))
            context.stroke(path, with: .color(Color.primary.opacity(0.85)), lineWidth: 1.5)
        }
        .allowsHitTesting(false)
    }

    /// The arc of `node`, or of the nearest folder above it that is drawn.
    private func visibleSegment(for node: FileNode) -> SunburstSegment? {
        var current: FileNode? = node
        while let candidate = current {
            if let segment = segments.first(where: { $0.node === candidate }) {
                return segment
            }
            current = candidate.parent
        }
        return nil
    }
}

/// The middle of the disc: what is on screen, and a click target to go up.
private struct SunburstCenter: View {
    @Environment(AppModel.self) private var model
    let focus: FileNode
    let diameter: CGFloat

    var body: some View {
        VStack(spacing: 3) {
            if focus.parent != nil {
                Image(systemName: "arrow.up")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            Text(model.title(for: focus))
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(Format.bytes(focus.size))
                .font(.title2.weight(.bold))
                .monospacedDigit()
            Text(Format.files(focus.fileCount))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .minimumScaleFactor(0.7)
        .frame(width: diameter * 0.78, height: diameter * 0.78)
        .allowsHitTesting(false)
    }
}
