import Foundation

/// Appends a profile's final text to a file the user chose (AD-104), for
/// example today's note. The path may contain `{date}`, `{time}` and `{app}`;
/// a model never decides where text is written. Files are coordinated, so an
/// iCloud folder such as an Obsidian vault is safe.
public enum FileAppendDelivery {
    public enum Failure: Error, LocalizedError {
        case unavailable(String)
        case write(String)

        public var errorDescription: String? {
            switch self {
            case .unavailable(let reason): reason
            case .write(let reason): String(localized: "Couldn't add the text to the file: \(reason.prefix(300))", bundle: .module)
            }
        }
    }

    /// The template with its fields filled in and `~` expanded.
    public static func resolvedPath(_ template: String, app: String?, date: Date = Date()) -> String {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        let time = DateFormatter()
        time.locale = Locale(identifier: "en_US_POSIX")
        time.dateFormat = "HH-mm"
        let appName = (app?.isEmpty == false ? app! : "Unknown App")
            .components(separatedBy: CharacterSet(charactersIn: "/:\\\0")).joined(separator: "-")
        let filled = template
            .replacingOccurrences(of: "{date}", with: day.string(from: date))
            .replacingOccurrences(of: "{time}", with: time.string(from: date))
            .replacingOccurrences(of: "{app}", with: appName)
        return (filled as NSString).expandingTildeInPath
    }

    /// Why text cannot be appended with this template now, or nil.
    public static func unavailableReason(template: String, app: String? = nil, date: Date = Date()) -> String? {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return String(localized: "Choose a file for this profile's text.", bundle: .module) }
        let path = resolvedPath(trimmed, app: app, date: date)
        guard path.hasPrefix("/"), !path.contains("\0") else {
            return String(localized: "Choose the file using its full path.", bundle: .module)
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
            return isDirectory.boolValue ? String(localized: "The chosen path is a folder. Choose a file.", bundle: .module) : nil
        }
        let folder = (path as NSString).deletingLastPathComponent
        guard FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory), isDirectory.boolValue else {
            return String(localized: "The folder for this profile's file doesn't exist.", bundle: .module)
        }
        return nil
    }

    /// Adds `text` as its own line at the end of the file, creating it when needed.
    public static func append(_ text: String, template: String, app: String?, date: Date = Date()) async throws {
        try Task.checkCancellation()
        if let reason = unavailableReason(template: template, app: app, date: date) { throw Failure.unavailable(reason) }
        let url = URL(fileURLWithPath: resolvedPath(template.trimmingCharacters(in: .whitespacesAndNewlines), app: app, date: date))
        try await Task.detached(priority: .userInitiated) {
            var coordinationError: NSError?
            var writeError: Error?
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { target in
                do { try appendLine(text, to: target) } catch { writeError = error }
            }
            if let error = coordinationError ?? (writeError as NSError?) { throw Failure.write(error.localizedDescription) }
        }.value
    }

    static func appendLine(_ text: String, to url: URL) throws {
        let manager = FileManager.default
        if !manager.fileExists(atPath: url.path) {
            guard manager.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteNoPermission)
            }
        }
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        var prefix = ""
        if end > 0 {
            try handle.seek(toOffset: end - 1)
            let last = try handle.read(upToCount: 1)
            if last != Data("\n".utf8) { prefix = "\n" }
            try handle.seekToEnd()
        }
        try handle.write(contentsOf: Data((prefix + text + "\n").utf8))
    }
}
