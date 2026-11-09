import SwiftUI

struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var isDropTarget = false

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                VStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                    Text("Overview")
                        .font(.system(size: 30, weight: .bold))
                    Text("See what is taking up space on your Mac.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 10) {
                    ForEach(model.volumes) { volume in
                        VolumeRow(volume: volume)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        model.scanHome()
                    } label: {
                        Label("Home Folder", systemImage: "house")
                    }
                    Button {
                        model.chooseFolder()
                    } label: {
                        Label("Choose Folder…", systemImage: "folder")
                    }
                }
                .controlSize(.large)

                Text("You can also drop a folder on this window.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 580)
            .padding(.horizontal, 40)
            .padding(.vertical, 48)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(8)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.scan(url: url)
            return true
        } isTargeted: { targeted in
            isDropTarget = targeted
        }
        .navigationTitle("Overview")
        .onAppear {
            model.refreshVolumes()
        }
    }
}

private struct VolumeRow: View {
    @Environment(AppModel.self) private var model
    let volume: VolumeInfo

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: volume.icon)
                .resizable()
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 6) {
                Text(volume.name)
                    .font(.headline)
                UsageBar(fraction: volume.usedFraction)
                Text("\(Format.bytes(volume.available)) available of \(Format.bytes(volume.total))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button("Scan") {
                model.scan(volume: volume)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// How full a disk is. Turns orange and red as it fills up.
private struct UsageBar: View {
    let fraction: Double

    private var color: Color {
        if fraction > 0.92 { return .red }
        if fraction > 0.80 { return .orange }
        return .accentColor
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(color)
                    .frame(width: max(proxy.size.width * fraction, 6))
            }
        }
        .frame(height: 6)
    }
}

struct ScanningView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let progress = model.scanner?.progress.snapshot ?? .init()
            VStack(spacing: 18) {
                Text("Scanning \(model.target?.title ?? "")…")
                    .font(.title2.weight(.semibold))

                if let expected = model.target?.expectedBytes, expected > 0 {
                    ProgressView(value: min(Double(progress.bytes) / Double(expected), 0.99))
                        .frame(width: 360)
                } else {
                    ProgressView()
                        .controlSize(.large)
                }

                Text("\(Format.files(progress.files)) · \(Format.bytes(progress.bytes))")
                    .font(.title3)
                    .monospacedDigit()

                Text(progress.currentPath)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 520)

                Button("Cancel", role: .cancel) {
                    model.cancelScan()
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Overview")
    }
}
