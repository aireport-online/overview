import AppKit
import Observation
import OverviewCore

enum ChartStyle: String, CaseIterable, Identifiable {
    case sunburst
    case treemap

    var id: String { rawValue }
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    enum Phase {
        case welcome
        case scanning
        case results
    }

    struct ScanTarget {
        var path: String
        var title: String
        /// Space in use on the volume when a whole volume is scanned; lets the
        /// progress bar show how far along the scan is.
        var expectedBytes: Int64?
    }

    private(set) var phase: Phase = .welcome
    private(set) var volumes: [VolumeInfo] = []

    // Scanning
    private(set) var target: ScanTarget?
    private(set) var scanner: DiskScanner?
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    // Results
    private(set) var root: FileNode?
    /// The folder the chart and list currently show.
    private(set) var focus: FileNode?
    /// Bumped whenever the tree changes, so views lay out again.
    private(set) var revision = 0
    private(set) var unreadableCount = 0
    private(set) var scanDuration: TimeInterval = 0
    var selection: FileNode?
    private(set) var hovered: FileNode?
    /// The last item the pointer was on; what the chart's context menu acts on.
    private(set) var contextNode: FileNode?
    var showsUnreadableBanner = true
    var pendingTrash: FileNode?
    var errorMessage: String?

    @ObservationIgnored private var largestCache: (focus: ObjectIdentifier, revision: Int, files: [FileNode])?

    private init() {}

    // MARK: Starting a scan

    func refreshVolumes() {
        volumes = VolumeInfo.mounted()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.prompt = String(localized: "Scan")
        panel.message = String(localized: "Choose a folder or disk to scan")
        if panel.runModal() == .OK, let url = panel.url {
            scan(url: url)
        }
    }

    func scanHome() {
        scan(url: FileManager.default.homeDirectoryForCurrentUser)
    }

    func scan(volume: VolumeInfo) {
        start(ScanTarget(path: volume.url.path, title: volume.name, expectedBytes: volume.total - volume.free))
    }

    func scan(url: URL) {
        let path = url.standardizedFileURL.path
        if let volume = VolumeInfo.mounted().first(where: { $0.url.standardizedFileURL.path == path }) {
            scan(volume: volume)
        } else {
            start(ScanTarget(path: path, title: FileManager.default.displayName(atPath: path), expectedBytes: nil))
        }
    }

    func rescan() {
        guard phase == .results, let target else { return }
        start(target)
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        scanner = nil
        phase = root == nil ? .welcome : .results
    }

    func showWelcome() {
        scanTask?.cancel()
        scanTask = nil
        scanner = nil
        clearResults()
        refreshVolumes()
        phase = .welcome
    }

    private func start(_ target: ScanTarget) {
        scanTask?.cancel()
        clearResults()

        let scanner = DiskScanner()
        self.scanner = scanner
        self.target = target
        phase = .scanning

        scanTask = Task { [weak self] in
            let started = Date()
            do {
                let tree = try await scanner.scan(path: target.path)
                self?.finish(tree, scanner: scanner, duration: Date().timeIntervalSince(started))
            } catch is CancellationError {
                // Cancelled by the user; `cancelScan` already updated the UI.
            } catch {
                self?.fail(error, scanner: scanner)
            }
        }
    }

    private func finish(_ tree: FileNode, scanner: DiskScanner, duration: TimeInterval) {
        guard self.scanner === scanner else { return }
        root = tree
        focus = tree
        unreadableCount = scanner.progress.snapshot.unreadableFolders
        showsUnreadableBanner = true
        scanDuration = duration
        revision += 1
        self.scanner = nil
        scanTask = nil
        phase = .results
    }

    private func fail(_ error: Error, scanner: DiskScanner) {
        guard self.scanner === scanner else { return }
        self.scanner = nil
        scanTask = nil
        phase = .welcome
        switch error {
        case ScanError.notFound(let path):
            errorMessage = String(localized: "“\(path)” could not be found.")
        case ScanError.notADirectory(let path):
            errorMessage = String(localized: "“\(path)” is not a folder.")
        default:
            errorMessage = error.localizedDescription
        }
    }

    private func clearResults() {
        root = nil
        focus = nil
        selection = nil
        hovered = nil
        contextNode = nil
        pendingTrash = nil
        largestCache = nil
    }

    // MARK: Navigating the results

    var canGoUp: Bool {
        phase == .results && focus?.parent != nil
    }

    func goUp() {
        guard phase == .results, let current = focus, let parent = current.parent else { return }
        focus = parent
        selection = current
        hovered = nil
    }

    /// Shows the contents of `node`, or for a file, its folder with the file selected.
    func zoom(to node: FileNode) {
        if node.isDirectory {
            focus = node
            selection = nil
        } else {
            focus = node.parent ?? focus
            selection = node
        }
        hovered = nil
    }

    /// A click in the treemap goes one level deeper, towards the tile clicked.
    func activateInTreemap(_ node: FileNode) {
        guard let focus, let child = node.child(under: focus) else { return }
        if child.isDirectory && !child.children.isEmpty {
            zoom(to: child)
        } else {
            selection = child
        }
    }

    /// A click in the sunburst opens the folder that was clicked.
    func activateInSunburst(_ node: FileNode) {
        if node.isDirectory && !node.children.isEmpty {
            zoom(to: node)
        } else if let parent = node.parent, parent !== focus {
            zoom(to: node)
        } else {
            selection = node
        }
    }

    func hover(_ node: FileNode?) {
        guard hovered !== node else { return }
        hovered = node
        if let node {
            contextNode = node
        }
    }

    func title(for node: FileNode) -> String {
        if node.parent == nil, let target {
            return target.title
        }
        return node.name
    }

    func largestFiles(in focus: FileNode) -> [FileNode] {
        if let cache = largestCache, cache.focus == focus.id, cache.revision == revision {
            return cache.files
        }
        let files = focus.largestFiles(limit: 100)
        largestCache = (focus.id, revision, files)
        return files
    }

    // MARK: Acting on items

    func reveal(_ node: FileNode) {
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    func copyPath(_ node: FileNode) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(node.path, forType: .string)
    }

    func trash(_ node: FileNode) {
        guard let parent = node.parent else { return }
        do {
            try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        if let focus, focus === node || focus.isDescendant(of: node) {
            self.focus = parent
        }
        selection = nil
        hovered = nil
        contextNode = nil
        node.removeFromParent()
        revision += 1
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
