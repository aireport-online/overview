// Switches the main display to the largest mode that fits in the given size.
// Only used on the build machine, whose screen starts out at 1024 x 768.
//
//   swift Scripts/display-mode.swift 1920 1080
import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3, let maxWidth = Int(arguments[1]), let maxHeight = Int(arguments[2]) else {
    FileHandle.standardError.write(Data("usage: display-mode.swift <max width> <max height>\n".utf8))
    exit(2)
}

let display = CGMainDisplayID()
let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
let modes = CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode] ?? []
for mode in modes {
    print("available: \(mode.width) x \(mode.height) points, \(mode.pixelWidth) x \(mode.pixelHeight) pixels")
}

let fitting = modes.filter { $0.width <= maxWidth && $0.height <= maxHeight }
guard let best = fitting.max(by: { ($0.width * $0.height, $0.pixelWidth) < ($1.width * $1.height, $1.pixelWidth) }) else {
    print("no display mode fits")
    exit(1)
}

var configuration: CGDisplayConfigRef?
CGBeginDisplayConfiguration(&configuration)
CGConfigureDisplayWithDisplayMode(configuration, display, best, nil)
let result = CGCompleteDisplayConfiguration(configuration, .forSession)
print("switched to \(best.width) x \(best.height) points, \(best.pixelWidth) x \(best.pixelHeight) pixels: \(result == .success ? "ok" : "failed")")
