import OverviewCore
import SwiftUI

struct ResultsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("chartStyle") private var chartStyle: ChartStyle = .sunburst

    var body: some View {
        VStack(spacing: 0) {
            if let focus = model.focus {
                BreadcrumbBar(focus: focus)
                Divider()
                if model.unreadableCount > 0 && model.showsUnreadableBanner {
                    UnreadableBanner(count: model.unreadableCount)
                    Divider()
                }
                HSplitView {
                    chart(for: focus)
                        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .windowBackgroundColor))
                    SidebarView(focus: focus, revision: model.revision)
                        .frame(minWidth: 280, idealWidth: 340, maxWidth: 520, maxHeight: .infinity)
                }
                Divider()
                StatusBar()
            }
        }
        .navigationTitle(model.target?.title ?? "")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    model.showWelcome()
                } label: {
                    Label("Start Over", systemImage: "chevron.backward")
                }
                .help("Choose another disk or folder")
            }
            ToolbarItem(placement: .navigation) {
                Button {
                    model.goUp()
                } label: {
                    Label("Enclosing Folder", systemImage: "arrow.up")
                }
                .disabled(!model.canGoUp)
                .help("Go to the enclosing folder")
            }
            ToolbarItem(placement: .principal) {
                Picker("Chart", selection: $chartStyle) {
                    Text("Sunburst").tag(ChartStyle.sunburst)
                    Text("Treemap").tag(ChartStyle.treemap)
                }
                .pickerStyle(.segmented)
                .help("Switch between the sunburst and the treemap")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.rescan()
                } label: {
                    Label("Scan Again", systemImage: "arrow.clockwise")
                }
                .help("Scan this location again")
            }
        }
        .confirmationDialog(
            "Move this item to the Trash?",
            isPresented: trashIsPresented,
            presenting: model.pendingTrash
        ) { node in
            Button("Move to Trash", role: .destructive) {
                model.trash(node)
            }
            Button("Cancel", role: .cancel) {}
        } message: { node in
            Text("“\(node.name)” (\(Format.bytes(node.size))) will be moved to the Trash. You can put it back from there.")
        }
    }

    @ViewBuilder
    private func chart(for focus: FileNode) -> some View {
        if focus.children.isEmpty || focus.size == 0 {
            ContentUnavailableView(
                "Nothing to show",
                systemImage: "folder",
                description: Text("This folder is empty or takes no space on disk.")
            )
        } else {
            switch chartStyle {
            case .sunburst:
                SunburstChart(focus: focus, revision: model.revision)
            case .treemap:
                TreemapChart(focus: focus, revision: model.revision)
            }
        }
    }

    private var subtitle: String {
        guard let root = model.root else { return "" }
        let seconds = model.scanDuration.formatted(.number.precision(.fractionLength(1)))
        return String(localized: "\(Format.bytes(root.size)) · \(Format.files(root.fileCount)) · scanned in \(seconds) s")
    }

    private var trashIsPresented: Binding<Bool> {
        Binding(
            get: { model.pendingTrash != nil },
            set: { if !$0 { model.pendingTrash = nil } }
        )
    }
}

/// The path from the scanned folder down to the folder on screen.
private struct BreadcrumbBar: View {
    @Environment(AppModel.self) private var model
    let focus: FileNode

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(focus.ancestry.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    Button {
                        model.zoom(to: node)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: index == 0 ? "internaldrive" : "folder.fill")
                                .foregroundStyle(.secondary)
                            Text(model.title(for: node))
                                .fontWeight(node === focus ? .semibold : .regular)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 30)
        .background(.bar)
    }
}

private struct UnreadableBanner: View {
    @Environment(AppModel.self) private var model
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("\(count) folders could not be read, so the totals are incomplete. Give Overview Full Disk Access to see everything.")
                .font(.callout)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Open Privacy Settings") {
                model.openPrivacySettings()
            }
            Button {
                model.showsUnreadableBanner = false
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Hide this message")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.yellow.opacity(0.14))
    }
}

/// Details of the item under the pointer, the selection or the folder on screen.
private struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            if let node = model.hovered ?? model.selection ?? model.focus {
                Text(node.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if node.isDirectory {
                    Text(Format.files(node.fileCount))
                        .foregroundStyle(.secondary)
                }
                if let root = model.root, root.size > 0 {
                    Text(Format.percent(Double(node.size) / Double(root.size)))
                        .foregroundStyle(.secondary)
                }
                Text(Format.bytes(node.size))
                    .fontWeight(.semibold)
            }
        }
        .font(.callout)
        .monospacedDigit()
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(.bar)
    }
}

/// Context menu for one file or folder.
struct NodeMenu: View {
    let node: FileNode

    var body: some View {
        let model = AppModel.shared
        if node.isDirectory && !node.children.isEmpty && node !== model.focus {
            Button("Zoom In") { model.zoom(to: node) }
            Divider()
        }
        Button("Show in Finder") { model.reveal(node) }
        Button("Copy Path") { model.copyPath(node) }
        if node.parent != nil {
            Divider()
            Button("Move to Trash…", role: .destructive) { model.pendingTrash = node }
        }
    }
}

/// Context menu of the charts: acts on the item the pointer was last on.
struct ChartMenu: View {
    var body: some View {
        if let node = AppModel.shared.contextNode {
            Text(node.name)
            NodeMenu(node: node)
        }
    }
}
