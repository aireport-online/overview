import AppKit
import OverviewCore
import SwiftUI

@main
struct OverviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared
    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage("animations") private var animations: AnimationSetting = .system

    var body: some Scene {
        Window("Overview", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Scan Folder…") { model.chooseFolder() }
                    .keyboardShortcut("o")
                Button("Scan Home Folder") { model.scanHome() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Divider()
                Button("Scan Again") { model.rescan() }
                    .keyboardShortcut("r")
                    .disabled(model.phase != .results)
                Button("Go to Enclosing Folder") { model.goUp() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .disabled(!model.canGoUp)
                Divider()
                Toggle("Sound Effects", isOn: $soundEnabled)
                Picker("Animations", selection: $animations) {
                    Text("Follow System Setting").tag(AnimationSetting.system)
                    Text("Always On").tag(AnimationSetting.on)
                    Text("Off").tag(AnimationSetting.off)
                }
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started with `swift run` there is no app bundle, so ask for a Dock
        // icon and keyboard focus explicitly.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()

        // The interface is its own dark world; keep menus and panels in tune.
        NSApp.appearance = NSAppearance(named: .darkAqua)

        // `open -a Overview --args -scan /some/folder` scans right away.
        if let path = UserDefaults.standard.string(forKey: "scan") {
            AppModel.shared.scan(url: URL(fileURLWithPath: path))
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// `-windowSize 1280x800` opens the window at exactly that size, for
    /// repeatable screenshots and recordings.
    static func applyRequestedSize(to window: NSWindow) {
        guard let request = UserDefaults.standard.string(forKey: "windowSize") else { return }
        let parts = request.split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2, let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = CGSize(width: min(parts[0], visible.width), height: min(parts[1], visible.height))
        let origin = CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        window.setFrame(CGRect(origin: origin, size: size), display: true)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var systemReducesMotion
    @AppStorage("animations") private var animations: AnimationSetting = .system

    private var reduceAnimations: Bool {
        switch animations {
        case .system: return systemReducesMotion
        case .on: return false
        case .off: return true
        }
    }

    var body: some View {
        ZStack {
            switch model.phase {
            case .welcome:
                WelcomeView()
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            case .scanning:
                ScanningView()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.92)),
                        // Leaves quickly, so it is gone before the chart opens.
                        removal: .opacity.combined(with: .scale(scale: 1.12)).animation(.easeIn(duration: 0.16))
                    ))
            case .results:
                ResultsView()
                    .transition(.opacity.animation(.easeOut(duration: 0.3).delay(0.12)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(duration: 0.55, bounce: 0.12), value: model.phase)
        .background {
            AuroraBackground()
                .ignoresSafeArea()
        }
        .background(WindowReader { AppDelegate.applyRequestedSize(to: $0) })
        // The window has no title bar of its own; this sits where the title would be.
        .overlay(alignment: .top) {
            WindowTitle()
                .frame(height: 28)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
        .environment(\.reduceAnimations, reduceAnimations)
        .preferredColorScheme(.dark)
        // A folder dropped on the Dock icon or opened with "Open With".
        .onOpenURL { url in
            model.scan(url: url)
        }
        .alert("Something went wrong", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}

private struct WindowTitle: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            if model.phase == .results, let target = model.target, let root = model.root {
                Text(target.title)
                    .fontWeight(.semibold)
                Text(summary(of: root))
                    .foregroundStyle(.secondary)
            } else {
                Text("Overview")
                    .fontWeight(.semibold)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(Color.white.opacity(0.9))
    }

    private func summary(of root: FileNode) -> String {
        let seconds = model.scanDuration.formatted(.number.precision(.fractionLength(1)))
        return String(localized: "\(Format.bytes(root.size)) · \(Format.files(root.fileCount)) · scanned in \(seconds) s")
    }
}
