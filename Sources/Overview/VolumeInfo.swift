import AppKit

/// A mounted disk as shown on the start screen.
struct VolumeInfo: Identifiable {
    let url: URL
    let name: String
    let total: Int64
    /// Space the system can make available, including purgeable space. This is
    /// the number Finder shows.
    let available: Int64
    /// Space that is free right now.
    let free: Int64
    let isInternal: Bool

    var id: URL { url }

    var usedFraction: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(total - available) / Double(total), 0), 1)
    }

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    static func mounted() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsInternalKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []

        return urls.compactMap { url -> VolumeInfo? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let total = values.volumeTotalCapacity, total > 0
            else { return nil }
            let free = Int64(values.volumeAvailableCapacity ?? 0)
            let important = values.volumeAvailableCapacityForImportantUsage ?? 0
            return VolumeInfo(
                url: url,
                name: values.volumeName ?? url.lastPathComponent,
                total: Int64(total),
                available: important > 0 ? important : free,
                free: free,
                isInternal: values.volumeIsInternal ?? false
            )
        }
    }
}
