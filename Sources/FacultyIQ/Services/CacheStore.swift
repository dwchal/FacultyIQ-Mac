import CryptoKit
import Foundation

/// File-backed cache for API responses, in
/// ~/Library/Application Support/FacultyIQ/cache. Mirrors the R app's
/// utils_cache.R: responses keyed by request hash, expiring after 7 days.
struct CacheStore: Sendable {
    static let shared = CacheStore()

    let expiryDays: Double = 7

    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FacultyIQ", isDirectory: true)
    }

    var cacheDirectory: URL {
        Self.supportDirectory.appendingPathComponent("cache", isDirectory: true)
    }

    private func fileURL(forKey key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent(name + ".json")
    }

    func data(forKey key: String) -> Data? {
        let url = fileURL(forKey: key)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < expiryDays * 86_400 else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    func store(_ data: Data, forKey key: String) {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(forKey: key))
    }

    func clear() {
        try? FileManager.default.removeItem(at: cacheDirectory)
    }

    var sizeDescription: String {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return "empty"
        }
        let bytes = files.reduce(0) { total, url in
            total + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%d files, %.1f MB", files.count, mb)
    }
}
