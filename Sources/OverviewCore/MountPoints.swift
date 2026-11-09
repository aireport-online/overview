import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Paths where other volumes are mounted. The scanner does not descend into
/// these, so a scan of `/` does not count external drives, network shares or
/// (on macOS) the data volume a second time through `/System/Volumes/Data`.
public enum MountPoints {
    public static func current() -> Set<String> {
        var result = Set<String>()
        #if canImport(Darwin)
        var buffer: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&buffer, MNT_NOWAIT)
        if let buffer, count > 0 {
            for index in 0..<Int(count) {
                var entry = buffer[index]
                let path = withUnsafePointer(to: &entry.f_mntonname) { pointer in
                    pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                        String(cString: $0)
                    }
                }
                result.insert(path)
            }
        }
        #else
        if let table = try? String(contentsOfFile: "/proc/self/mounts", encoding: .utf8) {
            for line in table.split(separator: "\n") {
                let fields = line.split(separator: " ")
                guard fields.count >= 2 else { continue }
                result.insert(unescape(String(fields[1])))
            }
        }
        #endif
        result.remove("/")
        return result
    }

    /// Decodes the octal escapes (`\040` for a space) used in /proc/self/mounts.
    static func unescape(_ field: String) -> String {
        guard field.contains("\\") else { return field }
        var bytes: [UInt8] = []
        let input = Array(field.utf8)
        var index = 0
        while index < input.count {
            if input[index] == UInt8(ascii: "\\"), index + 3 < input.count,
               let value = UInt8(String(decoding: input[(index + 1)...(index + 3)], as: UTF8.self), radix: 8) {
                bytes.append(value)
                index += 4
            } else {
                bytes.append(input[index])
                index += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
