import Foundation

enum UnreadableFile {
    /// Renames a file that failed to decode, so the next save cannot overwrite
    /// the user's data. It stays next to the original for manual recovery.
    @discardableResult
    static func setAside(_ url: URL) -> URL? {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = url.deletingPathExtension().appendingPathExtension("unreadable-\(stamp)-\(UUID().uuidString.prefix(8)).json")
        do { try FileManager.default.moveItem(at: url, to: backup); return backup }
        catch { return nil }
    }
}
