import SwiftUI

struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var isDropTarget = false
    /// Where the pointer is, from -1 to 1 on both axes; the hero leans towards it.
    @State private var lean = CGSize.zero

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 22) {
                    HeroDisc(lean: lean)
                        .frame(width: 210, height: 210)
                        .appear(0)

                    VStack(spacing: 6) {
                        Text("Overview")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("See what is taking up space on your Mac.")
                            .font(.title3)
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                    .appear(1)

                    VStack(spacing: 10) {
                        ForEach(Array(model.volumes.enumerated()), id: \.element.id) { index, volume in
                            LocationCard(
                                icon: volume.icon,
                                title: volume.name,
                                detail: String(localized: "\(Format.bytes(volume.available)) available of \(Format.bytes(volume.total))"),
                                usedFraction: volume.usedFraction
                            ) {
                                model.scan(volume: volume)
                            }
                            .appear(2 + index)
                        }
                        ForEach(Array(model.recents.enumerated()), id: \.element) { index, path in
                            LocationCard(
                                icon: NSWorkspace.shared.icon(forFile: path),
                                title: FileManager.default.displayName(atPath: path),
                                detail: (path as NSString).abbreviatingWithTildeInPath,
                                usedFraction: nil
                            ) {
                                model.scan(url: URL(fileURLWithPath: path))
                            }
                            .appear(2 + model.volumes.count + index)
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            model.scanHome()
                        } label: {
                            Label("Home Folder", systemImage: "house.fill")
                        }
                        Button {
                            model.chooseFolder()
                        } label: {
                            Label("Choose Folder…", systemImage: "folder.fill")
                        }
                    }
                    .buttonStyle(GlassButtonStyle())
                    .appear(3 + model.volumes.count + model.recents.count)

                    Text("You can also drop a folder on this window.")
                        .font(.callout)
                        .foregroundStyle(Color.white.opacity(0.5))
                        .appear(4 + model.volumes.count + model.recents.count)
                }
                .frame(maxWidth: 600)
                .padding(.horizontal, 40)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    lean = CGSize(
                        width: Self.offCentre(point.x, in: proxy.size.width),
                        height: Self.offCentre(point.y, in: proxy.size.height)
                    )
                case .ended:
                    lean = .zero
                }
            }
        }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Theme.pink, lineWidth: 3)
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
        .onAppear {
            model.refreshVolumes()
        }
    }

    /// Where `position` lies along `length`: -1 at the start, 0 in the middle, 1 at the end.
    private static func offCentre(_ position: CGFloat, in length: CGFloat) -> CGFloat {
        guard length > 0 else { return 0 }
        let value = position / length * 2 - 1
        return min(max(value, -1), 1)
    }
}

/// The glass disc: it floats, and tilts a little towards the pointer.
private struct HeroDisc: View {
    let lean: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false

    var body: some View {
        ZStack {
            Ellipse()
                .fill(Theme.pink.opacity(0.55))
                .frame(width: 170, height: 60)
                .blur(radius: 34)
                .offset(y: 86)
                .scaleEffect(floating ? 0.86 : 1.06)
            image
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .rotation3DEffect(.degrees(Double(lean.width) * 14), axis: (x: 0, y: 1, z: 0))
                .rotation3DEffect(.degrees(Double(-lean.height) * 10), axis: (x: 1, y: 0, z: 0))
                .offset(x: lean.width * 10, y: lean.height * 6)
                .animation(.spring(duration: 0.9, bounce: 0.35), value: lean)
                .offset(y: floating ? -7 : 7)
                .rotationEffect(.degrees(floating ? 2.5 : -2.5))
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true)) {
                floating = true
            }
        }
    }

    private var image: Image {
        Image(nsImage: Assets.hero ?? NSApp.applicationIconImage)
    }
}

/// A disk or a recent folder, with the button that scans it.
private struct LocationCard: View {
    let icon: NSImage
    let title: String
    let detail: String
    /// How full the disk is; nil for folders.
    let usedFraction: Double?
    let scan: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                if let usedFraction {
                    UsageBar(fraction: usedFraction)
                }
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ScanButton(action: scan)
        }
        .padding(.leading, 16)
        .padding(.trailing, 18)
        .padding(.vertical, 12)
        .glassPanel(cornerRadius: 18)
        .scaleEffect(hovering ? 1.015 : 1)
        .shadow(color: Color.black.opacity(hovering ? 0.35 : 0.15), radius: hovering ? 18 : 8, y: 6)
        .animation(.spring(duration: 0.35, bounce: 0.4), value: hovering)
        .onHover { hovering = $0 }
    }
}

/// How full a disk is. Fills up when it appears; warmer colours when nearly full.
private struct UsageBar: View {
    let fraction: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filled = false

    private var colors: [Color] {
        if fraction > 0.92 { return [.orange, .red] }
        if fraction > 0.80 { return [.yellow, .orange] }
        return [Theme.blue, Theme.violet]
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(proxy.size.width * (filled ? fraction : 0), 6))
            }
        }
        .frame(height: 6)
        .onAppear {
            if reduceMotion {
                filled = true
            } else {
                withAnimation(.spring(duration: 1.0, bounce: 0.2).delay(0.35)) {
                    filled = true
                }
            }
        }
    }
}
