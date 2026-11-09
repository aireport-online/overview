import SwiftUI

enum Format {
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    /// Sizes the way Finder shows them (1 GB = 1,000,000,000 bytes).
    static func bytes(_ value: Int64) -> String {
        byteFormatter.string(fromByteCount: value)
    }

    static func files(_ count: Int) -> String {
        count == 1 ? String(localized: "1 file") : String(localized: "\(count) files")
    }

    static func percent(_ fraction: Double) -> String {
        if fraction > 0 && fraction < 0.001 {
            return "<" + 0.001.formatted(.percent.precision(.fractionLength(1)))
        }
        return fraction.formatted(.percent.precision(.fractionLength(fraction < 0.1 ? 1 : 0)))
    }
}

/// Chart colours. Every direct child of the folder on screen gets its own hue,
/// and everything inside it a shade of that hue.
enum Palette {
    private static let hues: [Double] = [0.59, 0.07, 0.38, 0.77, 0.99, 0.49, 0.13, 0.89, 0.66, 0.28]

    private static func hue(_ branch: Int) -> Double {
        hues[branch % hues.count]
    }

    /// The colour of a branch in the list next to the chart.
    static func swatch(branch: Int) -> Color {
        Color(hue: hue(branch), saturation: 0.68, brightness: 0.84)
    }

    /// Sunburst arcs get lighter towards the outside; files are paler than folders.
    static func arc(branch: Int, ring: Int, isDirectory: Bool) -> Color {
        let saturation = max(0.24, 0.72 - 0.10 * Double(ring)) * (isDirectory ? 1 : 0.62)
        let brightness = min(0.97, 0.82 + 0.035 * Double(ring))
        return Color(hue: hue(branch), saturation: saturation, brightness: brightness)
    }

    /// A soft diagonal gradient that gives treemap tiles some depth.
    static func tile(branch: Int, depth: Int) -> Gradient {
        let step = Double(min(depth - 1, 5))
        let saturation = max(0.40, 0.66 - 0.04 * step)
        let brightness = min(0.84, 0.70 + 0.03 * step)
        return Gradient(colors: [
            Color(hue: hue(branch), saturation: saturation * 0.88, brightness: min(brightness + 0.10, 1)),
            Color(hue: hue(branch), saturation: saturation, brightness: brightness - 0.08),
        ])
    }

    /// The darker frame of a treemap folder, behind its tiles.
    static func frame(branch: Int, depth: Int) -> Color {
        let step = Double(min(depth - 1, 4))
        return Color(hue: hue(branch), saturation: 0.55, brightness: 0.30 + 0.06 * step)
    }

    /// Bundled small items in the sunburst.
    static let bundled = Color(white: 0.62)
}
