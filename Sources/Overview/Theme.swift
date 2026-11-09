import AppKit
import SwiftUI

/// Colours and shared pieces of the look: a deep gradient with drifting
/// light, and glass panels on top of it.
enum Theme {
    static let pink = Color(red: 1.0, green: 0.36, blue: 0.64)
    static let violet = Color(red: 0.58, green: 0.38, blue: 1.0)
    static let blue = Color(red: 0.27, green: 0.56, blue: 1.0)

    static let accent = LinearGradient(colors: [pink, violet], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Width of the list next to the chart.
    static let sidebarWidth: CGFloat = 340
}

/// Files that ship inside the app bundle.
enum Assets {
    static func url(_ name: String, _ fileExtension: String, subdirectory: String? = nil) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: fileExtension, subdirectory: subdirectory) {
            return url
        }
        // Started with `swift run` from the package folder there is no bundle:
        // read the files from the source tree instead.
        var path = FileManager.default.currentDirectoryPath + "/Resources/"
        if let subdirectory {
            path += subdirectory + "/"
        }
        path += name + "." + fileExtension
        return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }

    /// The glass disc on the start screen.
    static let hero: NSImage? = url("Hero", "png").flatMap { NSImage(contentsOf: $0) }
}

/// The window background: a dark gradient with three soft lights that drift
/// slowly, so the window never looks completely still.
struct AuroraBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.04, blue: 0.16),
                        Color(red: 0.13, green: 0.07, blue: 0.33),
                        Color(red: 0.30, green: 0.08, blue: 0.36),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                light(Theme.blue.opacity(0.50), diameter: size.width * 0.55)
                    .offset(x: -size.width * 0.32, y: -size.height * (drift ? 0.22 : 0.34))
                light(Theme.pink.opacity(0.42), diameter: size.width * 0.50)
                    .offset(x: size.width * (drift ? 0.30 : 0.38), y: size.height * 0.36)
                light(Theme.violet.opacity(0.45), diameter: size.width * 0.42)
                    .offset(x: size.width * (drift ? 0.12 : -0.04), y: -size.height * 0.05)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private func light(_ color: Color, diameter: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            .blur(radius: diameter * 0.32)
    }
}

extension View {
    /// A frosted panel with a hairline border.
    func glassPanel(cornerRadius: CGFloat = 20) -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
    }
}

/// Calls back once the view sits in a window, to adjust that window.
struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ProbeView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ProbeView: NSView {
        var onWindow: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                onWindow?(window)
                onWindow = nil
            }
        }
    }
}
