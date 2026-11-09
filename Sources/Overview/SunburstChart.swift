import OverviewCore
import SwiftUI

/// The folder on screen as a disc, with a ring for every level below it.
struct SunburstChart: View {
    @Environment(AppModel.self) private var model
    let focus: FileNode
    /// A new value makes the chart lay out and bloom again.
    let revision: Int

    private static let rings = 5

    private struct BloomKey: Hashable {
        let focus: ObjectIdentifier
        let revision: Int
    }

    var body: some View {
        GeometryReader { proxy in
            let geometry = SunburstGeometry(
                center: CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2),
                outerRadius: max(min(proxy.size.width, proxy.size.height) / 2 - 22, 40),
                rings: Self.rings,
                holeFraction: 0.31
            )
            let segments = SunburstLayout.layout(root: focus, rings: Self.rings)
            ZStack {
                Circle()
                    .fill(Theme.violet.opacity(0.35))
                    .frame(width: geometry.outerRadius * 1.9, height: geometry.outerRadius * 1.9)
                    .blur(radius: 60)
                    .position(geometry.center)

                SunburstBloom(segments: segments, geometry: geometry)
                    .id(BloomKey(focus: focus.id, revision: revision))
                SunburstHighlight(segments: segments, geometry: geometry)
                SunburstCenter(focus: focus, diameter: geometry.holeRadius * 2)
                    .position(geometry.center)
                    .id(BloomKey(focus: focus.id, revision: revision))
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
    /// The outline of a piece of ring. Built from points rather than `addArc`,
    /// so it uses exactly the angles that hit-testing uses.
    func ringPath(start: Double, end: Double, inner: CGFloat, outer: CGFloat) -> Path {
        let span = end - start
        let steps = max(Int((span / (Double.pi / 120)).rounded(.up)), 1)
        var path = Path()
        for step in 0...steps {
            let angle = start + span * Double(step) / Double(steps)
            let corner = point(angle: angle, radius: outer)
            if step == 0 {
                path.move(to: corner)
            } else {
                path.addLine(to: corner)
            }
        }
        for step in (0...steps).reversed() {
            let angle = start + span * Double(step) / Double(steps)
            path.addLine(to: point(angle: angle, radius: inner))
        }
        path.closeSubpath()
        return path
    }
}

/// Plays the opening of the chart once: the rings fan out clockwise from
/// twelve o'clock, the inner ring first.
private struct SunburstBloom: View {
    let segments: [SunburstSegment]
    let geometry: SunburstGeometry

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress = 0.0

    var body: some View {
        SunburstArcs(segments: segments, geometry: geometry, progress: reduceMotion ? 1 : progress)
            .onAppear {
                withAnimation(.easeOut(duration: 0.85)) {
                    progress = 1
                }
            }
    }
}

private struct SunburstArcs: View, Animatable {
    let segments: [SunburstSegment]
    let geometry: SunburstGeometry
    /// 0 is closed, 1 is fully open.
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    /// Each ring starts this much later than the one inside it.
    private static let ringDelay = 0.11

    var body: some View {
        Canvas { context, _ in
            let window = 1 - Self.ringDelay * Double(geometry.rings - 1)
            for segment in segments {
                let raw = (progress - Double(segment.ring) * Self.ringDelay) / window
                let linear = min(max(raw, 0), 1)
                guard linear > 0 else { continue }
                // Ease out, so every ring lands softly.
                let opening = 1 - pow(1 - linear, 3)

                let band = geometry.radii(ring: segment.ring)
                let path = geometry.ringPath(
                    start: segment.start * opening,
                    end: segment.end * opening,
                    inner: band.inner,
                    outer: band.inner + (band.outer - band.inner) * CGFloat(opening)
                )
                let color: Color
                if let node = segment.node {
                    color = Palette.arc(branch: segment.branch, ring: segment.ring, isDirectory: node.isDirectory)
                } else {
                    color = Palette.bundled
                }
                context.opacity = min(linear * 2, 1)
                context.fill(path, with: .color(color))
                context.stroke(path, with: .color(Palette.gap), lineWidth: 1.2)
            }
        }
    }
}

/// Lifts the arc under the pointer (or selected in the list) out of its ring.
/// Kept apart from the arcs so that moving the pointer does not redraw them.
private struct SunburstHighlight: View {
    @Environment(AppModel.self) private var model
    let segments: [SunburstSegment]
    let geometry: SunburstGeometry

    var body: some View {
        ZStack {
            if let target = model.hovered ?? model.selection, let segment = visibleSegment(for: target) {
                LiftedArc(segment: segment, geometry: geometry)
                    .id(target.id)
            }
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

private struct LiftedArc: View {
    let segment: SunburstSegment
    let geometry: SunburstGeometry

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lift = 0.0

    var body: some View {
        LiftedArcShape(segment: segment, geometry: geometry, lift: reduceMotion ? 1 : lift)
            .onAppear {
                withAnimation(.spring(duration: 0.4, bounce: 0.55)) {
                    lift = 1
                }
            }
    }
}

private struct LiftedArcShape: View, Animatable {
    let segment: SunburstSegment
    let geometry: SunburstGeometry
    /// 0 lies in the ring, 1 is fully lifted; the spring overshoots a little.
    var lift: Double

    var animatableData: Double {
        get { lift }
        set { lift = newValue }
    }

    var body: some View {
        Canvas { context, _ in
            let band = geometry.radii(ring: segment.ring)
            let amount = CGFloat(max(lift, 0))
            let path = geometry.ringPath(
                start: segment.start,
                end: segment.end,
                inner: band.inner - 1.5 * amount,
                outer: band.outer + 9 * amount
            )
            let color = Palette.litArc(branch: segment.branch, ring: segment.ring)
            var glow = context
            glow.addFilter(.shadow(color: color.opacity(0.9), radius: 14 * amount))
            glow.fill(path, with: .color(color))
            context.stroke(path, with: .color(Color.white.opacity(0.9)), lineWidth: 1.5)
        }
    }
}

/// The middle of the disc: what is on screen, and a click target to go up.
private struct SunburstCenter: View {
    @Environment(AppModel.self) private var model
    let focus: FileNode
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.42))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            VStack(spacing: 3) {
                if focus.parent != nil {
                    Image(systemName: "arrow.up")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                Text(model.title(for: focus))
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                CountUp(target: focus.size)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(Format.files(focus.fileCount))
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            .minimumScaleFactor(0.6)
            .padding(diameter * 0.14)
        }
        .frame(width: diameter - 8, height: diameter - 8)
        .allowsHitTesting(false)
    }
}
