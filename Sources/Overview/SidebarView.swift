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
            GlassSegmentedControl(
                selection: $tab,
                options: [(SidebarTab.contents, "Contents"), (SidebarTab.largest, "Largest Files")]
            )
            .padding(12)

            ZStack {
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
                    .transition(.opacity)
                case .largest:
                    ItemList(
                        nodes: model.largestFiles(in: focus),
                        focus: focus,
                        showsLocation: true,
                        hiddenCount: 0,
                        hiddenSize: 0
                    )
                    .transition(.opacity)
                }
            }
            // A new folder gets a new list, so its rows cascade in again.
            .id(ListKey(focus: focus.id, revision: revision))
        }
        .glassPanel(cornerRadius: 20, dark: true)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onChange(of: tab) {
            SoundPlayer.shared.play(.select)
        }
    }

    private struct ListKey: Hashable {
        let focus: ObjectIdentifier
        let revision: Int
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
                    location: showsLocation ? location(of: node) : nil,
                    isHovered: model.hovered === node
                )
                .tag(node.id)
                .listRowSeparatorTint(Color.white.opacity(0.08))
                .appear(min(index, 12), horizontal: true)
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
                    .foregroundStyle(Color.white.opacity(0.6))
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
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
            set: { id in model.select(nodes.first { $0.id == id }) }
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
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 9) {
            if let color {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 4, height: isHovered ? 34 : 28)
                    .shadow(color: color.opacity(isHovered ? 0.9 : 0), radius: 6)
            }
            Image(nsImage: NSWorkspace.shared.icon(forFile: node.path))
                .resizable()
                .frame(width: 24, height: 24)
                .scaleEffect(isHovered ? 1.15 : 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(node.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(Format.bytes(node.size))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.65))
                }
                if let location {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.head)
                } else {
                    ShareBar(fraction: fraction, color: color ?? Theme.violet)
                }
            }
        }
        .padding(.vertical, 4)
        .animation(.spring(duration: 0.3, bounce: 0.5), value: isHovered)
    }
}

/// The share of the folder on screen that one item takes. Grows from nothing
/// when it appears.
private struct ShareBar: View {
    let fraction: Double
    let color: Color

    @Environment(\.reduceAnimations) private var reduceMotion
    @State private var grown = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(color)
                    .frame(width: max(proxy.size.width * min(max(fraction, 0), 1) * (grown ? 1 : 0), 2))
            }
        }
        .frame(height: 4)
        .onAppear {
            if reduceMotion {
                grown = true
            } else {
                withAnimation(.spring(duration: 0.8, bounce: 0.2).delay(0.25)) {
                    grown = true
                }
            }
        }
    }
}
