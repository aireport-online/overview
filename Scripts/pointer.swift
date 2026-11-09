// Drives the pointer and keyboard from a list of steps, to try the app the
// way a person would. Used for the screenshots and the walkthrough recording.
// macOS only lets this through when the terminal has Accessibility access.
//
//   swift Scripts/pointer.swift <window x> <window y> < steps
//
// One step per line; positions are in points from the top left of the window:
//   move <x> <y> [seconds]   glide to a point
//   click | rightclick       press and release at the current point
//   key <code>               press a key (36 return, 53 escape)
//   wait <seconds>
//   mark <label>             print "<label> <unix time>", to line up sound later
import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3, let originX = Double(arguments[1]), let originY = Double(arguments[2]) else {
    FileHandle.standardError.write(Data("usage: pointer.swift <window x> <window y> < steps\n".utf8))
    exit(2)
}
if !CGPreflightPostEventAccess() {
    FileHandle.standardError.write(Data("warning: no permission to post events; the pointer may not move\n".utf8))
}

var position = CGEvent(source: nil)?.location ?? .zero

func post(_ type: CGEventType, button: CGMouseButton = .left) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: position, mouseButton: button)?
        .post(tap: .cghidEventTap)
}

func pause(_ seconds: Double) {
    usleep(UInt32(max(seconds, 0) * 1_000_000))
}

while let line = readLine() {
    let parts = line.split(separator: " ").map(String.init)
    guard let command = parts.first, !command.hasPrefix("#") else { continue }
    let numbers = parts.dropFirst().compactMap { Double($0) }

    switch command {
    case "move" where numbers.count >= 2:
        let target = CGPoint(x: originX + numbers[0], y: originY + numbers[1])
        let duration = numbers.count > 2 ? numbers[2] : 0.6
        let start = position
        let began = Date()
        while true {
            // Follow the clock rather than counting steps, so a glide takes
            // exactly as long as asked. Ease in and out, like a hand.
            let time = min(Date().timeIntervalSince(began) / max(duration, 0.001), 1)
            let eased = CGFloat(time * time * (3 - 2 * time))
            position = CGPoint(x: start.x + (target.x - start.x) * eased, y: start.y + (target.y - start.y) * eased)
            post(.mouseMoved)
            if time >= 1 { break }
            pause(1.0 / 120)
        }
    case "click":
        post(.leftMouseDown)
        pause(0.08)
        post(.leftMouseUp)
    case "rightclick":
        post(.rightMouseDown, button: .right)
        pause(0.08)
        post(.rightMouseUp, button: .right)
    case "key" where numbers.count == 1:
        let code = CGKeyCode(numbers[0])
        CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
        pause(0.05)
        CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
    case "wait" where numbers.count == 1:
        pause(numbers[0])
    case "mark" where parts.count == 2:
        print(parts[1], String(format: "%.3f", Date().timeIntervalSince1970))
        fflush(stdout)
    default:
        FileHandle.standardError.write(Data("skipping step: \(line)\n".utf8))
    }
}
