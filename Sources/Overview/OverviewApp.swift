import AppKit
import SwiftUI

@main
struct OverviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("Overview", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 880, minHeight: 560)
        }
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

        // `open -a Overview --args -scan /some/folder` scans right away.
        if let path = UserDefaults.standard.string(forKey: "scan") {
            AppModel.shared.scan(url: URL(fileURLWithPath: path))
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.phase {
            case .welcome:
                WelcomeView()
            case .scanning:
                ScanningView()
            case .results:
                ResultsView()
            }
        }
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
