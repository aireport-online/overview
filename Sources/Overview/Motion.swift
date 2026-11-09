import OverviewCore
import SwiftUI

/// How the app is asked to animate: follow System Settings, or always, or never.
enum AnimationSetting: String {
    case system
    case on
    case off
}

private struct ReduceAnimationsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True when views should appear in their final state instead of animating.
    var reduceAnimations: Bool {
        get { self[ReduceAnimationsKey.self] }
        set { self[ReduceAnimationsKey.self] = newValue }
    }
}

/// Fades and slides a view in when it appears. Views with a higher `index`
/// follow a little later, so a group arrives as a cascade.
struct Appear: ViewModifier {
    let index: Int
    var distance: CGFloat = 14
    var horizontal = false

    @Environment(\.reduceAnimations) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(x: shown || !horizontal ? 0 : distance, y: shown || horizontal ? 0 : distance)
            .onAppear {
                guard !shown else { return }
                if reduceMotion {
                    shown = true
                } else {
                    withAnimation(.spring(duration: 0.55, bounce: 0.25).delay(Double(index) * 0.06)) {
                        shown = true
                    }
                }
            }
    }
}

extension View {
    func appear(_ index: Int, horizontal: Bool = false) -> some View {
        modifier(Appear(index: index, horizontal: horizontal))
    }
}

/// A size that counts up (or down) to its value instead of jumping.
struct CountingBytes: View, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(Format.bytes(Int64(max(value, 0))))
            .monospacedDigit()
    }
}

/// Shows `target`, counting up from zero when it appears and from the old
/// value when it changes.
struct CountUp: View {
    let target: Int64
    var duration = 0.9

    @Environment(\.reduceAnimations) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        CountingBytes(value: reduceMotion ? Double(target) : shown)
            .onAppear { animate() }
            .onChange(of: target) { animate() }
    }

    private func animate() {
        withAnimation(.easeOut(duration: duration)) {
            shown = Double(target)
        }
    }
}

/// Scales a button down a little while it is pressed.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

/// A round glass button with one symbol.
struct GlassIconButton: View {
    let systemImage: String
    let help: LocalizedStringKey
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    init(_ systemImage: String, help: LocalizedStringKey, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(Color.white.opacity(isEnabled ? 0.92 : 0.3))
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(hovering && isEnabled ? 0.22 : 0.10), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .scaleEffect(hovering && isEnabled ? 1.1 : 1)
        .animation(.spring(duration: 0.3, bounce: 0.5), value: hovering)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// A glass capsule button with a title.
struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GlassButtonBody(configuration: configuration)
    }

    private struct GlassButtonBody: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(hovering ? 0.22 : 0.11), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? 0.95 : (hovering ? 1.04 : 1))
                .animation(.spring(duration: 0.3, bounce: 0.45), value: hovering)
                .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
                .onHover { hovering = $0 }
        }
    }
}

/// A segmented control whose selection slides from one option to the next.
struct GlassSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: LocalizedStringKey)]

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isSelected = option.value == selection
                Button {
                    withAnimation(.spring(duration: 0.4, bounce: 0.3)) {
                        selection = option.value
                    }
                } label: {
                    Text(option.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(isSelected ? 1 : 0.6))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.white.opacity(0.2))
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.25), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}

/// The round button that starts a scan: a gradient disc that sends out slow
/// rings while it waits, and swells under the pointer.
struct ScanButton: View {
    let action: () -> Void

    @Environment(\.reduceAnimations) private var reduceMotion
    @State private var hovering = false
    @State private var pulsing = false

    var body: some View {
        Button(action: action) {
            ZStack {
                ForEach(0..<2, id: \.self) { ring in
                    Circle()
                        .stroke(Theme.pink.opacity(0.6), lineWidth: 2)
                        .scaleEffect(pulsing ? 1.75 : 1)
                        .opacity(pulsing ? 0 : 0.8)
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: 2.2).repeatForever(autoreverses: false).delay(Double(ring) * 1.1),
                            value: pulsing
                        )
                }
                Circle()
                    .fill(Theme.accent)
                    .shadow(color: Theme.pink.opacity(hovering ? 0.8 : 0.45), radius: hovering ? 16 : 8)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                Text("Scan")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
            }
            .frame(width: 54, height: 54)
            .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .scaleEffect(hovering ? 1.1 : 1)
        .animation(.spring(duration: 0.35, bounce: 0.5), value: hovering)
        .onHover { hovering = $0 }
        .onAppear { pulsing = true }
    }
}
