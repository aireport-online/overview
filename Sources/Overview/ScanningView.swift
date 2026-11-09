import OverviewCore
import SwiftUI

struct ScanningView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
            let progress = model.scanner?.progress.snapshot ?? model.lastProgress
            VStack(spacing: 22) {
                Text("Scanning \(model.target?.title ?? "")…")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))

                ZStack {
                    ScanOrb(fraction: fraction(of: progress))
                    VStack(spacing: 4) {
                        CountingBytes(value: Double(progress.bytes))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .animation(.linear(duration: 0.2), value: progress.bytes)
                        Text(Format.files(progress.files))
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(Color.white.opacity(0.65))
                    }
                }
                .frame(width: 300, height: 300)

                Text(progress.currentPath.isEmpty ? " " : progress.currentPath)
                    .font(.callout)
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 520)

                Button("Cancel", role: .cancel) {
                    model.cancelScan()
                }
                .buttonStyle(GlassButtonStyle())
                .keyboardShortcut(.cancelAction)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// How far along the scan is, when a whole disk is scanned; nil otherwise.
    private func fraction(of progress: ScanProgress.Snapshot) -> Double? {
        guard let expected = model.target?.expectedBytes, expected > 0 else { return nil }
        return min(Double(progress.bytes) / Double(expected), 0.99)
    }
}

/// Rings of arcs turning at their own speed around the running total, inside
/// a progress ring: a sunburst that has not settled yet.
private struct ScanOrb: View {
    let fraction: Double?

    @Environment(\.reduceAnimations) private var reduceMotion
    @State private var spinning = false
    @State private var breathing = false

    private struct Arc {
        let inset: CGFloat
        let from: CGFloat
        let to: CGFloat
        let color: Color
        let seconds: Double
        let clockwise: Bool
    }

    private let arcs: [Arc] = [
        Arc(inset: 26, from: 0.02, to: 0.34, color: Theme.blue, seconds: 5.5, clockwise: true),
        Arc(inset: 26, from: 0.42, to: 0.60, color: Theme.pink, seconds: 5.5, clockwise: true),
        Arc(inset: 26, from: 0.68, to: 0.94, color: .orange, seconds: 5.5, clockwise: true),
        Arc(inset: 44, from: 0.10, to: 0.38, color: Theme.violet, seconds: 3.8, clockwise: false),
        Arc(inset: 44, from: 0.50, to: 0.86, color: .green, seconds: 3.8, clockwise: false),
        Arc(inset: 62, from: 0.00, to: 0.22, color: .cyan, seconds: 2.6, clockwise: true),
        Arc(inset: 62, from: 0.36, to: 0.70, color: Theme.pink, seconds: 2.6, clockwise: true),
    ]

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.violet.opacity(0.45))
                .blur(radius: 50)
                .scaleEffect(breathing ? 1.1 : 0.9)

            // Progress around the outside.
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 5)
            if let fraction {
                Circle()
                    .trim(from: 0, to: max(fraction, 0.01))
                    .stroke(
                        AngularGradient(colors: [Theme.blue, Theme.violet, Theme.pink], center: .center),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: fraction)
            } else {
                Circle()
                    .trim(from: 0, to: 0.22)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                    .animation(reduceMotion ? nil : .linear(duration: 1.6).repeatForever(autoreverses: false), value: spinning)
            }

            ForEach(arcs.indices, id: \.self) { index in
                let arc = arcs[index]
                Circle()
                    .trim(from: arc.from, to: arc.to)
                    .stroke(arc.color, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                    .padding(arc.inset)
                    .rotationEffect(.degrees(spinning ? (arc.clockwise ? 360 : -360) : 0))
                    .animation(reduceMotion ? nil : .linear(duration: arc.seconds).repeatForever(autoreverses: false), value: spinning)
                    .shadow(color: arc.color.opacity(0.6), radius: 6)
            }

            Circle()
                .fill(Color.black.opacity(0.38))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                .padding(78)
        }
        .onAppear {
            spinning = true
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }
}
