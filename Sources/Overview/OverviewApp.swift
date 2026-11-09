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

        // `Overview.app/Contents/MacOS/Overview /some/folder` scans right away.
        if let path = CommandLine.arguments.dropFirst().last, path.hasPrefix("/") {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                AppModel.shared.scan(url: URL(fileURLWithPath: path))
            }
        }
    }

    /// A folder dropped on the Dock icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first {
            AppModel.shared.scan(url: url)
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
