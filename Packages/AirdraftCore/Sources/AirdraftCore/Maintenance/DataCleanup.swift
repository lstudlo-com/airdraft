import Foundation
import Observation
import Darwin

public enum DataCleanupScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case history, audio, historyAndAudio, reset
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .history: "Remove History"
        case .audio: "Remove Audio Files"
        case .historyAndAudio: "Remove History and Audio Files"
        case .reset: "Reset App"
        }
    }
    public var removesHistory: Bool { self != .audio }
    public var removesAudio: Bool { self != .history }
    public var explanation: String {
        switch self {
        case .history: "Deletes dictation history and all meeting transcripts. Recordings, settings and models stay."
        case .audio: "Deletes all dictation and meeting audio, including interrupted recordings. Saved text, settings and models stay."
        case .historyAndAudio: "Deletes all dictation history, meeting transcripts, recordings and interrupted meetings. Settings and models stay."
        case .reset: "Deletes app data, settings, profiles, vocabulary, provider keys and downloaded models. Resets this app’s permissions. Quit when finished to restart setup. License and trial records stay."
        }
    }
}

public struct CleanupPreview: Sendable {
    public var historyCount: Int
    public var recordingCount: Int
    public var audioBytes: Int64
    public var managedBytes: Int64
    public var countsAvailable: Bool
    public init(historyCount: Int, recordingCount: Int, audioBytes: Int64, managedBytes: Int64, countsAvailable: Bool = true) {
        self.historyCount = historyCount; self.recordingCount = recordingCount
        self.audioBytes = audioBytes; self.managedBytes = managedBytes; self.countsAvailable = countsAvailable
    }
}

public enum CleanupError: LocalizedError {
    case busy, differentScope, invalidJournal, otherInstance, unsafeRoot, storageUnavailable
    public var errorDescription: String? {
        switch self {
        case .storageUnavailable: "History storage is unavailable. Check available disk space and reopen Airdraft."
        case .busy: "Stop recording and wait for current work to finish before removing data."
        case .differentScope: "Finish the interrupted cleanup before starting another one."
        case .invalidJournal: "The cleanup record could not be read. Keep Airdraft closed and check its data folder before removing anything."
        case .otherInstance: "Quit other Airdraft or Transcribar copies that share this data folder, then retry."
        case .unsafeRoot: "The app data folder is not a regular local directory. Cleanup stopped without following its link."
        }
    }
}

/// One durable, immutable deletion scope. Completed steps are never repeated by
/// Retry. Each step must tolerate a crash after its effect but before checkpoint.
@MainActor @Observable
public final class DataCleanupCoordinator {
    public struct Step {
        public let id: String
        public let title: String
        public let run: @MainActor () async throws -> Void
        public init(_ id: String, title: String, run: @escaping @MainActor () async throws -> Void) {
            self.id = id; self.title = title; self.run = run
        }
    }
    private struct Journal: Codable {
        var version = 1
        var scope: DataCleanupScope
        var completed: [String] = []
    }
    public private(set) var isRunning = false
    public private(set) var pendingScope: DataCleanupScope?
    public private(set) var completedSteps: [String] = []
    public private(set) var currentStep: String?
    public private(set) var error: String?
    public private(set) var finishedScope: DataCleanupScope?
    public var blocksWork: Bool { isRunning || pendingScope != nil || invalidJournal }
    private var invalidJournal = false
    private let journalURL: URL

    public init(directory: URL) {
        journalURL = directory.appendingPathComponent("cleanup.json")
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: journalURL.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.referenceCount] as? NSNumber)?.intValue == 1 else { throw CleanupError.invalidJournal }
            let journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: journalURL))
            guard journal.version == 1 else { throw CleanupError.invalidJournal }
            pendingScope = journal.scope; completedSteps = journal.completed
        } catch {
            invalidJournal = true; self.error = CleanupError.invalidJournal.localizedDescription
        }
    }

    public func execute(_ scope: DataCleanupScope, prepare: @MainActor () async throws -> Void,
                        steps: [Step], finish: @MainActor (Bool) -> Void = { _ in }) async {
        guard !isRunning else { return }
        guard !invalidJournal else { error = CleanupError.invalidJournal.localizedDescription; return }
        guard pendingScope == nil || pendingScope == scope else { error = CleanupError.differentScope.localizedDescription; return }
        isRunning = true; error = nil; finishedScope = nil
        defer { isRunning = false; currentStep = nil; finish(finishedScope == scope) }
        do {
            // Preparation checks busy/sibling processes before any destructive step.
            try await prepare()
            pendingScope = scope
            try checkpoint(scope)
            for step in steps where !completedSteps.contains(step.id) {
                currentStep = step.title
                try await step.run()
                completedSteps.append(step.id)
                try checkpoint(scope)
            }
            try FileManager.default.removeItem(at: journalURL)
            pendingScope = nil; completedSteps = []; finishedScope = scope
        } catch { self.error = error.localizedDescription }
    }

    private func checkpoint(_ scope: DataCleanupScope) throws {
        try FileManager.default.createDirectory(at: journalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Journal(scope: scope, completed: completedSteps))
        try data.write(to: journalURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journalURL.path)
        let handle = try FileHandle(forWritingTo: journalURL)
        defer { try? handle.close() }
        try handle.synchronize()
    }
}

/// One writer owns the data directory for its entire lifetime, including reset.
/// The lock file survives reset so another process cannot lock a different inode.
public final class DataDirectoryLease: @unchecked Sendable {
    private let descriptor: Int32
    public let holdsLease = true
    public init(directory: URL) throws {
        try ManagedDataFiles.validateRoot(directory)
        let url = directory.appendingPathComponent(".airdraft-data.lock")
        descriptor = open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(.EACCES) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor); throw CleanupError.otherInstance
        }
    }
    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
}

public enum ManagedDataFiles {
    public static func validateRoot(_ directory: URL) throws {
        guard directory.isFileURL, directory.standardizedFileURL.path != "/",
              (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw CleanupError.unsafeRoot
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    public static func bytes(in directory: URL) throws -> Int64 {
        guard FileManager.default.fileExists(atPath: directory.path) else { return 0 }
        guard let iterator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in iterator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            if values.isSymbolicLink == true { iterator.skipDescendants(); continue }
            if values.isRegularFile == true { total += Int64(values.fileSize ?? 0) }
        }
        return total
    }
    /// The entire designated app-data root belongs to the app. Never follows
    /// symlink children; deleting a link leaves its external target untouched.
    public static func resetContents(in directory: URL) throws {
        try validateRoot(directory)
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            guard !["cleanup.json", ".airdraft-data.lock"].contains(url.lastPathComponent) else { continue }
            try FileManager.default.removeItem(at: url)
        }
    }
}
