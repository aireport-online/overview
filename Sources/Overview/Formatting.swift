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
    private static let hues: [Double] = [0.60, 0.07, 0.37, 0.76, 0.93, 0.50, 0.13, 0.84, 0.66, 0.28]

    private static func hue(_ branch: Int) -> Double {
        hues[branch % hues.count]
    }

    /// The colour of a branch in the list next to the chart.
    static func swatch(branch: Int) -> Color {
        Color(hue: hue(branch), saturation: 0.72, brightness: 1.0)
    }

    /// Sunburst arcs get lighter towards the outside; files are paler than folders.
    static func arc(branch: Int, ring: Int, isDirectory: Bool) -> Color {
        let saturation = max(0.28, 0.80 - 0.12 * Double(ring)) * (isDirectory ? 1 : 0.68)
        let brightness = min(1.0, 0.93 + 0.02 * Double(ring))
        return Color(hue: hue(branch), saturation: saturation, brightness: brightness)
    }

    /// The arc under the pointer: the same hue, lit up.
    static func litArc(branch: Int, ring: Int) -> Color {
        Color(hue: hue(branch), saturation: max(0.22, 0.55 - 0.08 * Double(ring)), brightness: 1.0)
    }

    /// A soft diagonal gradient that gives treemap tiles some depth.
    static func tile(branch: Int, depth: Int) -> Gradient {
        let step = Double(min(depth - 1, 5))
        let saturation = max(0.45, 0.74 - 0.04 * step)
        let brightness = min(0.96, 0.82 + 0.03 * step)
        return Gradient(colors: [
            Color(hue: hue(branch), saturation: saturation * 0.85, brightness: min(brightness + 0.08, 1)),
            Color(hue: hue(branch), saturation: saturation, brightness: brightness - 0.12),
        ])
    }

    /// The darker frame of a treemap folder, behind its tiles.
    static func frame(branch: Int, depth: Int) -> Color {
        let step = Double(min(depth - 1, 4))
        return Color(hue: hue(branch), saturation: 0.62, brightness: 0.26 + 0.06 * step)
    }

    /// Bundled small items in the sunburst.
    static let bundled = Color(white: 0.8).opacity(0.5)

    /// The dark lines between arcs.
    static let gap = Color(red: 0.07, green: 0.05, blue: 0.18)
}
