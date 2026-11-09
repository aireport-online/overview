// Prints the id of the first normal window of a process, for `screencapture -l`.
//
//   swift Scripts/window-id.swift <pid>
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2, let pid = Int(CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("usage: window-id.swift <pid>\n".utf8))
    exit(2)
}

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows {
    guard (window[kCGWindowOwnerPID as String] as? Int) == pid,
          (window[kCGWindowLayer as String] as? Int) == 0,
          let id = window[kCGWindowNumber as String] as? Int
    else { continue }
    print(id)
    exit(0)
}
exit(1)
