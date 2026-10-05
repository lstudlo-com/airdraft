import Foundation
import GRDB
import Darwin

public struct DictationRecord: Codable, Sendable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "dictation"

    public var id: Int64?
    public var createdAt: Date
    public var appBundleId: String?
    public var appName: String?
    public var windowTitle: String?
    public var url: String?
    public var mode: String
    public var family: String
    public var rawTranscript: String
    public var refinedText: String
    public var finalText: String
    public var language: String?
    public var asrEngine: String
    public var llmEngine: String?
    public var promptVersion: String?
    public var audioSeconds: Double
    public var asrMs: Int
    public var llmMs: Int
    public var inserted: Bool
    public var error: String?
    public var audioFilename: String?
    public var recordingID: String?
    public var outputDestination: String?
    public var outputSucceeded: Bool?

    public init(
        id: Int64? = nil,
        createdAt: Date = Date(),
        appBundleId: String? = nil,
        appName: String? = nil,
        windowTitle: String? = nil,
        url: String? = nil,
        mode: String,
        family: String,
        rawTranscript: String,
        refinedText: String,
        finalText: String,
        language: String? = nil,
        asrEngine: String,
        llmEngine: String? = nil,
        promptVersion: String? = nil,
        audioSeconds: Double,
        asrMs: Int,
        llmMs: Int,
        inserted: Bool,
        error: String? = nil,
        audioFilename: String? = nil,
        recordingID: String? = nil,
        outputDestination: String? = nil,
        outputSucceeded: Bool? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.appBundleId = appBundleId
        self.appName = appName
        self.windowTitle = windowTitle
        self.url = url
        self.mode = mode
        self.family = family
        self.rawTranscript = rawTranscript
        self.refinedText = refinedText
        self.finalText = finalText
        self.language = language
        self.asrEngine = asrEngine
        self.llmEngine = llmEngine
        self.promptVersion = promptVersion
        self.audioSeconds = audioSeconds
        self.asrMs = asrMs
        self.llmMs = llmMs
        self.inserted = inserted
        self.error = error
        self.audioFilename = audioFilename
        self.recordingID = recordingID
        self.outputDestination = outputDestination
        self.outputSucceeded = outputSucceeded
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// SQLite history at ~/Library/Application Support/Transcribar/history.sqlite.
public final class HistoryStore: Sendable {
    let dbQueue: DatabaseQueue
    private let audioDirectory: URL?
    // GRDB serializes SQL; this also covers the corresponding sidecar operations.
    let audioLock = NSLock()

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("history.sqlite")
        audioDirectory = directory.appendingPathComponent("Recordings", isDirectory: true)
        dbQueue = try DatabaseQueue(path: url.path, configuration: Self.configuration)
        try migrate()
    }

    public init(inMemory: Bool) throws {
        audioDirectory = nil
        dbQueue = try DatabaseQueue(configuration: Self.configuration)
        try migrate()
    }

    /// Release the database handle before a disposable fixture removes its files.
    /// Call only after its pipeline work has been cancelled or completed.
    public func close() throws {
        try dbQueue.close()
    }

    /// Deleted dictations are overwritten on disk, not left in free pages.
    private static var configuration: Configuration {
        var config = Configuration()
        config.busyMode = .timeout(5)
        config.prepareDatabase { db in try db.execute(sql: "PRAGMA secure_delete = ON") }
        return config
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: DictationRecord.databaseTableName) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("appBundleId", .text).indexed()
                t.column("appName", .text)
                t.column("windowTitle", .text)
                t.column("url", .text)
                t.column("mode", .text).notNull()
                t.column("family", .text).notNull()
                t.column("rawTranscript", .text).notNull()
                t.column("refinedText", .text).notNull()
                t.column("finalText", .text).notNull()
                t.column("language", .text)
                t.column("asrEngine", .text).notNull()
                t.column("llmEngine", .text)
                t.column("promptVersion", .text)
                t.column("audioSeconds", .double).notNull()
                t.column("asrMs", .integer).notNull()
                t.column("llmMs", .integer).notNull()
                t.column("inserted", .boolean).notNull()
                t.column("error", .text)
            }
        }
        migrator.registerMigration("v2") { db in
            try db.alter(table: DictationRecord.databaseTableName) { t in
                t.add(column: "audioFilename", .text)
            }
        }
        migrator.registerMigration("v3") { db in
            try db.alter(table: DictationRecord.databaseTableName) { t in
                t.add(column: "outputDestination", .text)
                t.add(column: "outputSucceeded", .boolean)
            }
        }
        migrator.registerMigration("v4-recording-assets") { [self] db in
            try db.create(table: RecordingAsset.databaseTableName) { t in
                t.primaryKey("id", .text)
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("filename", .text).notNull().unique()
                t.column("duration", .double).notNull()
                t.column("source", .text).notNull()
            }
            try db.alter(table: DictationRecord.databaseTableName) { t in
                t.add(column: "recordingID", .text).references(RecordingAsset.databaseTableName, onDelete: .setNull).indexed()
            }
            // Adopt existing sidecars in place. Invalid or missing paths never
            // become assets; the text remains available with no audio attached.
            for record in try DictationRecord.fetchAll(db) where record.audioFilename != nil {
                if let url = try existingAudioURL(named: record.audioFilename) {
                    let asset = RecordingAsset(filename: url.lastPathComponent, createdAt: record.createdAt,
                                               duration: record.audioSeconds)
                    try asset.insert(db, onConflict: .ignore)
                    try db.execute(sql: "UPDATE dictation SET recordingID = ? WHERE id = ?", arguments: [asset.id, record.id])
                } else {
                    try db.execute(sql: "UPDATE dictation SET audioFilename = NULL WHERE id = ?", arguments: [record.id])
                }
            }
        }
        migrator.registerMigration("v5-media-documents") { db in
            try db.create(table: "mediaDocument") { t in
                t.primaryKey("id", .text)
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("recordingID", .text).references("recordingAsset", onDelete: .setNull).indexed()
                t.column("title", .text).notNull()
                t.column("text", .text).notNull()
                t.column("revision", .integer).notNull()
                t.column("payload", .blob).notNull()
            }
        }
        try migrator.migrate(dbQueue)
    }

    @discardableResult
    public func save(_ record: DictationRecord, samples: [Float]? = nil) throws -> DictationRecord {
        try audioLock.withLock {
            var r = record
            // An insert may only attach audio created by this store, never a supplied path.
            r.audioFilename = nil
            r.recordingID = nil
            var writtenURL: URL?
            do {
                return try dbQueue.write { db in
                    // Take SQLite's writer lease before creating the file. Another store
                    // pruning this directory must not mistake an in-flight save for an orphan.
                    if let samples, !samples.isEmpty, audioDirectory != nil {
                        writtenURL = try writeAudio(samples)
                        r.audioFilename = writtenURL?.lastPathComponent
                        if let filename = r.audioFilename {
                            let asset = RecordingAsset(filename: filename, createdAt: r.createdAt, duration: r.audioSeconds)
                            try asset.insert(db)
                            r.recordingID = asset.id
                        }
                    }
                    try r.insert(db)
                    return r
                }
            } catch {
                let saveError = error
                if let writtenURL {
                    do { try removeAudio(named: writtenURL.lastPathComponent) }
                    catch { throw AudioStorageError.cleanupFailed(saveError, error) }
                }
                throw saveError
            }
        }
    }

    /// Keep audio without carrying any transcript or app context into its asset.
    public func saveRecording(samples: [Float], source: RecordingAsset.Source = .dictation,
                              createdAt: Date = Date()) throws -> RecordingAsset {
        try audioLock.withLock {
            var written: URL?
            do {
                return try dbQueue.write { db in
                    let url = try writeAudio(samples)
                    written = url
                    let asset = RecordingAsset(filename: url.lastPathComponent, createdAt: createdAt,
                                               duration: Double(samples.count) / AudioRecorder.sampleRate, source: source)
                    try asset.insert(db)
                    return asset
                }
            } catch {
                if let written { try removeAudio(named: written.lastPathComponent) }
                throw error
            }
        }
    }

    public func cleanupPreview() throws -> CleanupPreview {
        try audioLock.withLock {
            try dbQueue.read { db in
                CleanupPreview(historyCount: try DictationRecord.fetchCount(db) + Int.fetchOne(db, sql: "SELECT COUNT(*) FROM mediaDocument")!,
                               recordingCount: try RecordingAsset.fetchCount(db),
                               audioBytes: try audioDirectory.map { try ManagedDataFiles.bytes(in: $0) } ?? 0,
                               managedBytes: try audioDirectory.map { try ManagedDataFiles.bytes(in: $0.deletingLastPathComponent()) } ?? 0)
            }
        }
    }

    /// Only UUID-named regular files inside this store are exposed for playback.
    public func audioURL(for record: DictationRecord) -> URL? {
        audioLock.withLock { try? existingAudioURL(named: record.audioFilename) }
    }

    public func audioSamples(for record: DictationRecord) throws -> [Float] {
        try audioLock.withLock {
            guard let url = try existingAudioURL(named: record.audioFilename) else {
                throw AudioStorageError.unavailable
            }
            return try AudioFile.load(path: url.path)
        }
    }

    /// A nil cutoff removes saved dictation audio while retaining text history.
    /// Explicit media imports and meetings have independent retention.
    /// Every pass also reconciles missing references and unfinished/orphaned writes.
    public func pruneAudio(olderThan cutoff: Date?) throws {
        try audioLock.withLock {
            try dbQueue.write { db in
                var retained = Set<String>()
                for asset in try RecordingAsset.fetchAll(db) {
                    let expired = asset.source == .dictation && (cutoff.map { asset.createdAt < $0 } ?? true)
                    if expired {
                        try removeAudio(named: asset.filename)
                    } else if try existingAudioURL(named: asset.filename) != nil {
                        retained.insert(asset.filename)
                        continue
                    }
                    try detachAndDelete(asset, in: db)
                }
                try db.execute(sql: "UPDATE dictation SET audioFilename = NULL WHERE recordingID IS NULL")
                try removeOrphanAudio(retaining: retained)
            }
        }
    }

    public func recent(limit: Int = 200, query: String = "", offset: Int = 0) throws -> [DictationRecord] {
        try dbQueue.read { db in
            var request = DictationRecord.order(Column("createdAt").desc, Column("id").desc).limit(limit, offset: max(0, offset))
            let q = query.trimmingCharacters(in: .whitespaces)
            if !q.isEmpty {
                let pattern = "%\(q)%"
                request = request.filter(
                    Column("rawTranscript").like(pattern) || Column("finalText").like(pattern) || Column("appName").like(pattern)
                )
            }
            return try request.fetchAll(db)
        }
    }

    /// Final texts of recent dictations into the same app, oldest first.
    public func recentFinals(appBundleId: String?, within seconds: TimeInterval = 20 * 60, limit: Int = 3) throws -> [String] {
        guard let appBundleId else { return [] }
        return try dbQueue.read { db in
            let since = Date().addingTimeInterval(-seconds)
            let rows = try DictationRecord
                .filter(Column("appBundleId") == appBundleId && Column("createdAt") >= since)
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
            return rows.reversed().map(\.finalText)
        }
    }

    public func delete(id: Int64) throws {
        try audioLock.withLock {
            try dbQueue.write { db in
                guard let record = try DictationRecord.fetchOne(db, key: id) else { return }
                // A migrated sidecar may be referenced by more than one old row.
                let shared = try record.recordingID.map { assetID in
                    try DictationRecord.filter(Column("recordingID") == assetID).fetchCount(db) > 1
                } ?? false
                // Remove the file first. A failure leaves the row available for retry.
                if !shared { try removeAudio(named: record.audioFilename) }
                _ = try DictationRecord.deleteOne(db, key: id)
                if let assetID = record.recordingID,
                   try DictationRecord.filter(Column("recordingID") == assetID).fetchCount(db) == 0 {
                    _ = try RecordingAsset.deleteOne(db, key: assetID)
                }
            }
        }
    }

    public func deleteAll() throws {
        try audioLock.withLock {
            try dbQueue.write { db in
                for asset in try RecordingAsset.fetchAll(db) {
                    try removeAudio(named: asset.filename)
                }
                try removeOrphanAudio(retaining: [])
                _ = try DictationRecord.deleteAll(db)
                try db.execute(sql: "DELETE FROM mediaDocument")
                _ = try RecordingAsset.deleteAll(db)
            }
            try dbQueue.vacuum()
        }
    }

    /// Removes transcript text and app context, retaining only independent audio metadata.
    public func deleteHistoryKeepingAudio() throws {
        try audioLock.withLock {
            try dbQueue.write { db in
                _ = try DictationRecord.deleteAll(db)
                try db.execute(sql: "DELETE FROM mediaDocument")
            }
            try dbQueue.vacuum()
        }
    }

    public func deleteAllAudio() throws {
        try audioLock.withLock {
            try dbQueue.write { db in
                for asset in try RecordingAsset.fetchAll(db) {
                    try removeAudio(named: asset.filename)
                    try detachAndDelete(asset, in: db)
                }
                try db.execute(sql: "UPDATE dictation SET audioFilename = NULL, recordingID = NULL")
                try removeOrphanAudio(retaining: [])
            }
        }
    }

    public func deleteRecording(id: String) throws {
        try audioLock.withLock {
            try dbQueue.write { db in
                guard let asset = try RecordingAsset.fetchOne(db, key: id) else { return }
                try removeAudio(named: asset.filename)
                try detachAndDelete(asset, in: db)
            }
        }
    }

    private func detachAndDelete(_ asset: RecordingAsset, in db: Database) throws {
        try db.execute(sql: "UPDATE dictation SET audioFilename = NULL, recordingID = NULL WHERE recordingID = ?",
                       arguments: [asset.id])
        _ = try RecordingAsset.deleteOne(db, key: asset.id)
    }

    public func audioURL(for asset: RecordingAsset) -> URL? {
        audioLock.withLock { try? dbQueue.read { db in
            guard let stored = try RecordingAsset.fetchOne(db, key: asset.id), stored.filename == asset.filename else { return nil }
            return try existingAudioURL(named: stored.filename)
        } }
    }

    public func audioSamples(for asset: RecordingAsset) throws -> [Float] {
        try audioLock.withLock {
            // A writer lease also prevents another store from removing the file
            // between validating its reference and decoding it.
            try dbQueue.write { db in
                guard let stored = try RecordingAsset.fetchOne(db, key: asset.id),
                      let url = try existingAudioURL(named: stored.filename) else { throw AudioStorageError.unavailable }
                return try AudioFile.load(path: url.path)
            }
        }
    }

    public func recording(id: String) throws -> RecordingAsset? {
        try dbQueue.read { db in try RecordingAsset.fetchOne(db, key: id) }
    }

    /// Copies the stored bytes under the same writer lease as deletion. The
    /// destination is published only after a complete copy; the source is never moved.
    public func exportRecording(id: String, to destination: URL, replacing: Bool = false) throws {
        try audioLock.withLock {
            try dbQueue.write { db in
                guard destination.isFileURL,
                      let asset = try RecordingAsset.fetchOne(db, key: id),
                      let source = try existingAudioURL(named: asset.filename),
                      let directory = audioDirectory else { throw AudioStorageError.unavailable }
                let target = destination.standardizedFileURL.resolvingSymlinksInPath()
                let managed = directory.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path
                guard target.path != managed, !target.path.hasPrefix(managed + "/") else {
                    throw AudioStorageError.exportInManagedDirectory
                }
                let temporary = target.deletingLastPathComponent().appendingPathComponent(".Airdraft-\(UUID().uuidString).pending")
                do {
                    try FileManager.default.copyItem(at: source, to: temporary)
                    let handle = try FileHandle(forWritingTo: temporary)
                    defer { try? handle.close() }
                    try handle.synchronize()
                    if replacing {
                        guard rename(temporary.path, target.path) == 0 else {
                            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                        }
                    } else {
                        try FileManager.default.moveItem(at: temporary, to: target)
                    }
                } catch {
                    let exportError = error
                    do { try removeManagedFile(at: temporary) }
                    catch { throw AudioStorageError.cleanupFailed(exportError, error) }
                    throw exportError
                }
            }
        }
    }

    /// Filters before paging and resolves availability off the UI thread.
    public func recordings(limit: Int = 200, query: String = "", offset: Int = 0) throws -> RecordingPage {
        try audioLock.withLock {
            try dbQueue.read { db in
                let pageSize = max(1, min(limit, 500))
                let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
                var scan = max(0, offset)
                var entries: [RecordingPage.Entry] = []
                let filter = query.isEmpty ? "" : """
                    WHERE a.id LIKE ? OR EXISTS (
                        SELECT 1 FROM dictation d WHERE d.recordingID = a.id AND
                        (d.rawTranscript LIKE ? OR d.finalText LIKE ? OR d.appName LIKE ?))
                    OR EXISTS (SELECT 1 FROM mediaDocument m WHERE m.recordingID = a.id AND (m.title LIKE ? OR m.text LIKE ?))
                    """
                while entries.count < pageSize {
                    let pattern = "%\(query)%"
                    var arguments: StatementArguments = query.isEmpty ? [] : [pattern, pattern, pattern, pattern, pattern, pattern]
                    arguments += [pageSize, scan]
                    let batch = try RecordingAsset.fetchAll(db, sql: """
                        SELECT a.* FROM recordingAsset a \(filter)
                        ORDER BY a.createdAt DESC, a.id DESC LIMIT ? OFFSET ?
                        """, arguments: arguments)
                    for asset in batch {
                        scan += 1
                        guard try existingAudioURL(named: asset.filename) != nil else { continue }
                        let dictation = try DictationRecord.filter(Column("recordingID") == asset.id).fetchOne(db)
                        let document = try Row.fetchOne(db, sql: "SELECT payload, recordingID FROM mediaDocument WHERE recordingID = ? ORDER BY createdAt DESC LIMIT 1", arguments: [asset.id]).map(Self.decodeDocument)
                        entries.append(.init(asset: asset, dictation: dictation, document: document))
                        if entries.count == pageSize { return RecordingPage(entries: entries, nextOffset: scan) }
                    }
                    if batch.count < pageSize { return RecordingPage(entries: entries, nextOffset: nil) }
                }
                return RecordingPage(entries: entries, nextOffset: nil)
            }
        }
    }

    private enum AudioStorageError: LocalizedError {
        case unavailable, unsafeLocation, invalidSamples, exportInManagedDirectory
        case cleanupFailed(Error, Error)

        var errorDescription: String? {
            switch self {
            case .exportInManagedDirectory: return "Choose a folder outside Airdraft’s managed data folder so your exported copy survives app cleanup."
            case .unavailable: return "This recording is no longer available."
            case .unsafeLocation: return "The recording location is not a regular file or private folder."
            case .invalidSamples: return "The recording contains invalid audio samples."
            case let .cleanupFailed(original, cleanup):
                return "\(original.localizedDescription) Audio cleanup also failed: \(cleanup.localizedDescription). Retry clearing saved audio."
            }
        }
    }

    private static func isAudioFilename(_ filename: String, extension suffix: String = "wav") -> Bool {
        guard filename.hasSuffix(".\(suffix)") else { return false }
        let stem = String(filename.dropLast(suffix.count + 1))
        return stem.count == 36 && UUID(uuidString: stem)?.uuidString == stem.uppercased()
    }

    /// attributesOfItem uses lstat, so symbolic links are never accepted as audio.
    private func attributes(at url: URL) throws -> [FileAttributeKey: Any]? {
        do { return try FileManager.default.attributesOfItem(atPath: url.path) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }

    func checkedAudioDirectory(create: Bool = false) throws -> URL? {
        guard let directory = audioDirectory else { return nil }
        var info = try attributes(at: directory)
        if info == nil, create {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            info = try attributes(at: directory)
        }
        guard let info else { return nil }
        guard info[.type] as? FileAttributeType == .typeDirectory else {
            throw AudioStorageError.unsafeLocation
        }
        if create {
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
        return directory
    }

    func existingAudioURL(named filename: String?) throws -> URL? {
        guard let filename, Self.isAudioFilename(filename),
              let directory = try checkedAudioDirectory() else { return nil }
        let url = directory.appendingPathComponent(filename)
        guard let info = try attributes(at: url),
              info[.type] as? FileAttributeType == .typeRegular,
              (info[.referenceCount] as? NSNumber)?.intValue == 1 else { return nil }
        return url
    }

    private func writeAudio(_ samples: [Float]) throws -> URL {
        guard samples.count <= (Int(UInt32.max) - 36) / 2, samples.allSatisfy(\.isFinite) else {
            throw AudioStorageError.invalidSamples
        }
        guard let directory = try checkedAudioDirectory(create: true) else { throw AudioStorageError.unavailable }
        let stem = UUID().uuidString
        let temporary = directory.appendingPathComponent("\(stem).pending")
        let destination = directory.appendingPathComponent("\(stem).wav")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: WAVEncoder.encode(samples: samples))
            try handle.synchronize()
            try handle.close()
            // Same-directory rename publishes only a completely written WAV.
            try FileManager.default.moveItem(at: temporary, to: destination)
            return destination
        } catch {
            let writeError = error
            try? handle.close()
            do { try removeManagedFile(at: temporary) }
            catch { throw AudioStorageError.cleanupFailed(writeError, error) }
            throw writeError
        }
    }

    private func removeAudio(named filename: String?) throws {
        guard let filename, Self.isAudioFilename(filename),
              let directory = try checkedAudioDirectory() else { return }
        try removeManagedFile(at: directory.appendingPathComponent(filename))
    }

    private func removeManagedFile(at url: URL) throws {
        guard let info = try attributes(at: url) else { return }
        guard info[.type] as? FileAttributeType == .typeRegular else { throw AudioStorageError.unsafeLocation }
        // Never use recursive FileManager deletion on an unverified path.
        guard unlink(url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    private func removeOrphanAudio(retaining filenames: Set<String>) throws {
        guard let directory = try checkedAudioDirectory() else { return }
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let name = url.lastPathComponent
            guard !filenames.contains(name),
                  Self.isAudioFilename(name) || Self.isAudioFilename(name, extension: "pending") || Self.isAudioFilename(name, extension: "upload") else { continue }
            // Unexpected directories and links belong to neither our writer nor cleanup.
            guard try attributes(at: url)?[.type] as? FileAttributeType == .typeRegular else { continue }
            try removeManagedFile(at: url)
        }
    }

    public func count() throws -> Int {
        try dbQueue.read { db in try DictationRecord.fetchCount(db) }
    }

    public struct Stats: Sendable, Equatable {
        public var dictations: Int
        public var words: Int
        public var audioSeconds: Double
        public var apps: Int
        /// Words per minute of speech.
        public var wordsPerMinute: Int { audioSeconds > 1 ? Int(Double(words) / (audioSeconds / 60)) : 0 }
        /// Typing the same words at 40 wpm minus the time spent speaking.
        public var minutesSaved: Int { max(0, Int(Double(words) / 40 - audioSeconds / 60)) }
    }

    /// Aggregates over all history, or over the last `days` days.
    public func stats(days: Int? = nil) throws -> Stats {
        try dbQueue.read { db in
            let rows = try Self.rows(db, days: days, now: Date())
            return Self.stats(rows)
        }
    }

    /// Everything the Home page summarises, computed locally from history.
    public struct Overview: Sendable, Equatable {
        /// One dictation, drawn as a bar in the Home waveform.
        public struct Pulse: Sendable, Equatable, Identifiable {
            public var id: Int64
            public var date: Date
            public var words: Int
            public var wordsPerMinute: Int
            public var appName: String?
            public var finalText: String
        }

        public struct AppShare: Sendable, Equatable {
            public var bundleId: String?
            public var name: String
            public var words: Int
        }

        public var stats: Stats
        /// The most recent dictations in the period, oldest first.
        public var pulses: [Pulse]
        /// Apps ranked by words dictated in the period.
        public var topApps: [AppShare]
        /// Consecutive days with a dictation, ending today or yesterday, over all history.
        public var streakDays: Int
        /// Distinct days with a dictation in the period.
        public var activeDays: Int
        /// Words in the period's longest dictation.
        public var longestWords: Int

        public static let empty = Overview(stats: Stats(dictations: 0, words: 0, audioSeconds: 0, apps: 0),
                                           pulses: [], topApps: [], streakDays: 0, activeDays: 0, longestWords: 0)
    }

    public func overview(days: Int? = nil, now: Date = Date(), calendar: Calendar = .current, calendarDay: Bool = false,
                         pulseLimit: Int = 48, appLimit: Int = 3) throws -> Overview {
        try dbQueue.read { db in
            let rows = try Self.rows(db, days: days, now: now, since: calendarDay ? calendar.startOfDay(for: now) : nil)
            let counted = rows.map { ($0, DictationPipeline.approximateWordCount($0.finalText)) }

            let pulses = counted.suffix(pulseLimit).compactMap { record, words -> Overview.Pulse? in
                guard let id = record.id else { return nil }
                return Overview.Pulse(id: id, date: record.createdAt, words: words,
                               wordsPerMinute: record.audioSeconds > 1 ? Int(Double(words) / (record.audioSeconds / 60)) : 0,
                               appName: record.appName, finalText: record.finalText)
            }

            var shares: [String: Overview.AppShare] = [:]
            for (record, words) in counted {
                guard let key = record.appBundleId ?? record.appName else { continue }
                shares[key, default: .init(bundleId: record.appBundleId, name: record.appName ?? key, words: 0)].words += words
            }
            let topApps = shares.values
                .sorted { $0.words != $1.words ? $0.words > $1.words : $0.name < $1.name }
                .prefix(appLimit)

            let allDates = try Date.fetchAll(db, DictationRecord.select(Column("createdAt")))
            let activeDays = Set(rows.map { calendar.startOfDay(for: $0.createdAt) }).count
            return Overview(stats: Self.stats(rows), pulses: Array(pulses), topApps: Array(topApps),
                            streakDays: Self.streak(allDates, now: now, calendar: calendar),
                            activeDays: activeDays, longestWords: counted.map(\.1).max() ?? 0)
        }
    }

    private static func rows(_ db: Database, days: Int?, now: Date, since: Date? = nil) throws -> [DictationRecord] {
        var request = DictationRecord.order(Column("createdAt"), Column("id"))
        if let since {
            request = request.filter(Column("createdAt") >= since && Column("createdAt") <= now)
        } else if let days {
            request = request.filter(Column("createdAt") >= now.addingTimeInterval(-Double(days) * 86_400))
        }
        return try request.fetchAll(db)
    }

    private static func stats(_ rows: [DictationRecord]) -> Stats {
        let words = rows.reduce(0) { $0 + DictationPipeline.approximateWordCount($1.finalText) }
        let seconds = rows.reduce(0.0) { $0 + $1.audioSeconds }
        let apps = Set(rows.compactMap { $0.appBundleId ?? $0.appName }).count
        return Stats(dictations: rows.count, words: words, audioSeconds: seconds, apps: apps)
    }

    /// A streak survives until the end of the day after the last dictation.
    static func streak(_ dates: [Date], now: Date, calendar: Calendar) -> Int {
        let days = Set(dates.map { calendar.startOfDay(for: $0) })
        var day = calendar.startOfDay(for: now)
        if !days.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day), days.contains(yesterday) else { return 0 }
            day = yesterday
        }
        var count = 0
        while days.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}
