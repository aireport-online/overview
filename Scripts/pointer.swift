// Moves the pointer to a point on screen, and optionally clicks there. Used
// by Scripts/screenshots.sh to try the charts the way a person would. macOS
// only lets this through when the terminal has Accessibility access.
//
//   swift Scripts/pointer.swift move|click <x> <y>
import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 4, ["move", "click"].contains(arguments[1]),
      let x = Double(arguments[2]), let y = Double(arguments[3])
else {
    FileHandle.standardError.write(Data("usage: pointer.swift move|click <x> <y>\n".utf8))
    exit(2)
}
if !CGPreflightPostEventAccess() {
    FileHandle.standardError.write(Data("warning: no permission to post events; the pointer may not move\n".utf8))
}

let point = CGPoint(x: x, y: y)

func post(_ type: CGEventType) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    usleep(120_000)
}

// Arrive in two steps, so the window sees the pointer move.
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: x - 3, y: y - 3), mouseButton: .left)?
    .post(tap: .cghidEventTap)
usleep(120_000)
post(.mouseMoved)
if arguments[1] == "click" {
    post(.leftMouseDown)
    post(.leftMouseUp)
}
