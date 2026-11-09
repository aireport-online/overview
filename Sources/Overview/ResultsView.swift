import OverviewCore
import SwiftUI

struct ResultsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("chartStyle") private var chartStyle: ChartStyle = .sunburst
    @AppStorage("soundEnabled") private var soundEnabled = true

    var body: some View {
        VStack(spacing: 10) {
            if let focus = model.focus {
                TopBar(focus: focus, chartStyle: $chartStyle, soundEnabled: $soundEnabled)

                if model.unreadableCount > 0 && model.showsUnreadableBanner {
                    UnreadableBanner(count: model.unreadableCount)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                HStack(spacing: 14) {
                    chart(for: focus)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    SidebarView(focus: focus, revision: model.revision)
                        .frame(width: Theme.sidebarWidth)
                        .appear(2, horizontal: true)
                }

                StatusBar()
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .animation(.spring(duration: 0.4, bounce: 0.2), value: model.showsUnreadableBanner)
        .onChange(of: chartStyle) {
            SoundPlayer.shared.play(.select)
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
            ZStack {
                switch chartStyle {
                case .sunburst:
                    SunburstChart(focus: focus, revision: model.revision)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                case .treemap:
                    TreemapChart(focus: focus, revision: model.revision)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
        }
    }

    private var trashIsPresented: Binding<Bool> {
        Binding(
            get: { model.pendingTrash != nil },
            set: { if !$0 { model.pendingTrash = nil } }
        )
    }
}

/// Navigation on the left, view options on the right.
private struct TopBar: View {
    @Environment(AppModel.self) private var model
    let focus: FileNode
    @Binding var chartStyle: ChartStyle
    @Binding var soundEnabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            GlassIconButton("chevron.backward", help: "Choose another disk or folder") {
                model.showWelcome()
            }
            GlassIconButton("arrow.up", help: "Go to the enclosing folder") {
                model.goUp()
            }
            .disabled(!model.canGoUp)

            Breadcrumbs(focus: focus)

            Spacer(minLength: 8)

            GlassSegmentedControl(
                selection: $chartStyle,
                options: [(ChartStyle.sunburst, "Sunburst"), (ChartStyle.treemap, "Treemap")]
            )
            .frame(width: 190)

            GlassIconButton(
                soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                help: soundEnabled ? "Turn sound effects off" : "Turn sound effects on"
            ) {
                soundEnabled.toggle()
            }
            GlassIconButton("arrow.clockwise", help: "Scan this location again") {
                model.rescan()
            }
        }
        .frame(height: 36)
        .appear(0)
    }
}

/// The path from the scanned folder down to the folder on screen.
private struct Breadcrumbs: View {
    @Environment(AppModel.self) private var model
    let focus: FileNode

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(focus.ancestry.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.35))
                    }
                    Button {
                        model.zoom(to: node)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: index == 0 ? "internaldrive.fill" : "folder.fill")
                                .foregroundStyle(Color.white.opacity(0.6))
                            Text(model.title(for: node))
                                .fontWeight(node === focus ? .semibold : .regular)
                                .foregroundStyle(Color.white.opacity(node === focus ? 1 : 0.75))
                        }
                        .font(.system(size: 13))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(node === focus ? 0.14 : 0), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 4)
            .animation(.spring(duration: 0.4, bounce: 0.3), value: focus.id)
        }
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
            .buttonStyle(GlassButtonStyle())
            GlassIconButton("xmark", help: "Hide this message") {
                model.showsUnreadableBanner = false
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassPanel(cornerRadius: 16)
    }
}

/// Details of the item under the pointer, the selection or the folder on screen.
private struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            if let node = model.hovered ?? model.selection ?? model.focus {
                Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                    .foregroundStyle(Color.white.opacity(0.5))
                Text(node.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(Color.white.opacity(0.7))
                Spacer(minLength: 8)
                if node.isDirectory {
                    Text(Format.files(node.fileCount))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                if let root = model.root, root.size > 0 {
                    Text(Format.percent(Double(node.size) / Double(root.size)))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                Text(Format.bytes(node.size))
                    .fontWeight(.semibold)
                    .contentTransition(.numericText())
            }
        }
        .font(.callout)
        .monospacedDigit()
        .padding(.horizontal, 14)
        .frame(height: 34)
        .glassPanel(cornerRadius: 12)
        .appear(3)
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
