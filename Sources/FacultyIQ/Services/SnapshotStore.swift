import Foundation

/// Append-only metric history, in
/// ~/Library/Application Support/FacultyIQ/snapshots.json — separate from
/// state.json so roster replacements and Clear Roster never touch it.
enum SnapshotStore {
    static var fileURL: URL {
        CacheStore.supportDirectory.appendingPathComponent("snapshots.json")
    }

    static func load() -> [MetricSnapshot] {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshots = try? JSONDecoder().decode([MetricSnapshot].self, from: data) else {
            return []
        }
        return snapshots
    }

    static func save(_ snapshots: [MetricSnapshot]) {
        try? FileManager.default.createDirectory(
            at: CacheStore.supportDirectory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(snapshots) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
