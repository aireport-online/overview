import OverviewCore
import SwiftUI

enum SidebarTab: String {
    case contents
    case largest
}

/// The list next to the chart: the contents of the folder on screen, or the
/// largest files anywhere below it.
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("sidebarTab") private var tab: SidebarTab = .contents
    let focus: FileNode
    let revision: Int

    /// Folders can hold hundreds of thousands of items; the list shows the
    /// largest ones and sums up the rest.
    private static let rowLimit = 500

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                Text("Contents").tag(SidebarTab.contents)
                Text("Largest Files").tag(SidebarTab.largest)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)
            Divider()

            switch tab {
            case .contents:
                let shown = Array(focus.children.prefix(Self.rowLimit))
                let hidden = focus.children.dropFirst(Self.rowLimit)
                ItemList(
                    nodes: shown,
                    focus: focus,
                    showsLocation: false,
                    hiddenCount: hidden.count,
                    hiddenSize: hidden.reduce(0) { $0 + $1.size }
                )
            case .largest:
                ItemList(
                    nodes: model.largestFiles(in: focus),
                    focus: focus,
                    showsLocation: true,
                    hiddenCount: 0,
                    hiddenSize: 0
                )
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct ItemList: View {
    @Environment(AppModel.self) private var model
    let nodes: [FileNode]
    let focus: FileNode
    let showsLocation: Bool
    let hiddenCount: Int
    let hiddenSize: Int64

    var body: some View {
        List(selection: selection) {
            ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                ItemRow(
                    node: node,
                    color: showsLocation ? nil : Palette.swatch(branch: index),
                    fraction: focus.size > 0 ? Double(node.size) / Double(focus.size) : 0,
                    location: showsLocation ? location(of: node) : nil
                )
                .tag(node.id)
                .onHover { inside in
                    if inside {
                        model.hover(node)
                    } else if model.hovered === node {
                        model.hover(nil)
                    }
                }
            }
            if hiddenCount > 0 {
                Text("and \(hiddenCount) smaller items (\(Format.bytes(hiddenSize)))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.inset)
        .contextMenu(forSelectionType: ObjectIdentifier.self) { ids in
            if let node = node(for: ids) {
                NodeMenu(node: node)
            }
        } primaryAction: { ids in
            guard let node = node(for: ids) else { return }
            if node.isDirectory && !node.children.isEmpty {
                model.zoom(to: node)
            } else {
                model.reveal(node)
            }
        }
    }

    private var selection: Binding<ObjectIdentifier?> {
        Binding(
            get: { model.selection?.id },
            set: { id in model.selection = nodes.first { $0.id == id } }
        )
    }

    private func node(for ids: Set<ObjectIdentifier>) -> FileNode? {
        guard let id = ids.first else { return nil }
        return nodes.first { $0.id == id }
    }

    /// The folder a file is in, relative to the folder on screen.
    private func location(of node: FileNode) -> String {
        guard let parent = node.parent, parent !== focus else { return model.title(for: focus) }
        let base = focus.path
        let path = parent.path
        guard path.hasPrefix(base) else { return path }
        return String(path.dropFirst(base.count).drop { $0 == "/" })
    }
}

private struct ItemRow: View {
    let node: FileNode
    let color: Color?
    let fraction: Double
    let location: String?

    var body: some View {
        HStack(spacing: 8) {
            if let color {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 4, height: 30)
            }
            Image(nsImage: NSWorkspace.shared.icon(forFile: node.path))
                .resizable()
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(node.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(Format.bytes(node.size))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if let location {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                } else {
                    ShareBar(fraction: fraction, color: color ?? .accentColor)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

/// The share of the folder on screen that one item takes.
private struct ShareBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(color)
                    .frame(width: max(proxy.size.width * min(max(fraction, 0), 1), 2))
            }
        }
        .frame(height: 4)
    }
}
