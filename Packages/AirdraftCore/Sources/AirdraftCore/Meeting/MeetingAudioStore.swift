import AVFoundation
import Foundation

public enum MeetingTrack: String, Codable, CaseIterable, Sendable { case microphone, system }
public struct MeetingDraft: Codable, Identifiable, Sendable {
    public var id: String
    public var createdAt: Date
    public var microphone: Bool
    public var interruptions: [String] = []
}
public enum MeetingError: LocalizedError {
    case storage, invalidClock, permission, noDisplay, sourceGone, diskSpace, noAudio
    public var errorDescription: String? {
        switch self {
        case .storage: return "The meeting recording could not be saved. Check disk access, then recover it from Meetings."
        case .invalidClock: return "The audio clock changed. Recording stopped to preserve the saved timeline."
        case .permission: return "Allow Microphone and Screen & System Audio Recording in System Settings, then try again."
        case .noDisplay: return "No display is available for meeting audio capture. Connect a display and try again."
        case .sourceGone: return "The selected meeting app is no longer running. Choose it again."
        case .diskSpace: return "Recording stopped because disk space is low. Free space, then recover the saved audio from Meetings."
        case .noAudio: return "No audio buffers were received. Check the selected app, microphone and permissions."
        }
    }
}

/// Single serial capture queue owns this writer. Raw PCM files survive process interruption;
/// their lengths, rather than a buffered header, determine the recoverable duration.
public final class MeetingAudioWriter {
    public static let sampleRate = 16_000
    private let folder: URL
    private var handles: [MeetingTrack: FileHandle] = [:]
    private var ends: [MeetingTrack: Int] = [:]
    private var draft: MeetingDraft
    private var lastSyncFrame = 0
    private var closed = false
    public var duration: Double { Double(ends.values.max() ?? 0) / 16_000 }
    public var id: String { draft.id }
    public func end(of track: MeetingTrack) -> Double { Double(ends[track] ?? 0) / 16_000 }
    public init(directory: URL, microphone: Bool) throws {
        let root = directory.appendingPathComponent("MeetingStaging", isDirectory: true)
        try MeetingAudioStore.ensureDirectory(root)
        draft = MeetingDraft(id: UUID().uuidString, createdAt: Date(), microphone: microphone)
        folder = root.appendingPathComponent(draft.id, isDirectory: true)
        try MeetingAudioStore.ensureDirectory(folder)
        try MeetingAudioStore.save(draft, in: folder)
        for track in MeetingTrack.allCases {
            let url = folder.appendingPathComponent(track.rawValue + ".pcm")
            guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw MeetingError.storage }
            handles[track] = try FileHandle(forWritingTo: url)
        }
    }
    deinit { for handle in handles.values { try? handle.close() } }
    /// Offset is measured on the common SCStream presentation clock, not callback arrival time.
    public func append(_ samples: [Float], track: MeetingTrack, at seconds: Double) throws {
        guard !closed, seconds.isFinite, seconds > -5, seconds <= MediaConfiguration.maximumDuration,
              !samples.isEmpty, samples.count <= 5 * Self.sampleRate,
              samples.allSatisfy(\.isFinite), let handle = handles[track] else { throw MeetingError.invalidClock }
        let start = Int((seconds * 16_000).rounded())
        let previous = ends[track] ?? 0
        let skipped = max(0, previous - start)
        guard skipped < samples.count else { return } // Duplicate or late buffer; never overwrite captured audio.
        let position = max(previous, start)
        let count = min(samples.count - skipped, Int(MediaConfiguration.maximumDuration * 16_000) - position)
        guard count > 0 else { throw MediaError.tooLong }
        if position - previous > 4_000 {
            try note("\(track == .microphone ? "Microphone" : "App audio") gap at \(String(format: "%.1f", Double(previous) / 16_000)) seconds (\(String(format: "%.1f", Double(position - previous) / 16_000)) seconds).")
        }
        let pcm = samples[skipped..<(skipped + count)].map { Int16(max(-1, min(1, $0)) * 32767).littleEndian }
        try handle.seek(toOffset: UInt64(position * 2)) // Sparse holes preserve missing time without unbounded allocations.
        try pcm.withUnsafeBytes { try handle.write(contentsOf: Data($0)) }
        ends[track] = position + count
        if position + count - lastSyncFrame >= 32_000 {
            try handle.synchronize(); lastSyncFrame = position + count
            let free = try folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
            if let free, free < 256 * 1_024 * 1_024 { throw MeetingError.diskSpace }
        }
    }
    public func note(_ issue: String) throws {
        if draft.interruptions.count < 100 && !draft.interruptions.contains(issue) {
            draft.interruptions.append(issue)
            try MeetingAudioStore.save(draft, in: folder)
        }
    }
    public func finish(reason: String? = nil) throws -> MeetingDraft {
        guard !closed else { return draft }
        if let reason { try note(reason) }
        if (ends[.system] ?? 0) == 0 { try note("No app audio was received.") }
        if draft.microphone && (ends[.microphone] ?? 0) == 0 { try note("No microphone audio was received.") }
        let longest = ends.values.max() ?? 0
        for track in MeetingTrack.allCases where track == .system || draft.microphone {
            if let end = ends[track], longest - end > 4_000 { try note("\(track == .microphone ? "Microphone" : "App audio") ended \(String(format: "%.1f", Double(longest - end) / 16_000)) seconds before the recording stopped.") }
        }
        for handle in handles.values { try handle.synchronize(); try handle.close() }
        handles.removeAll(); closed = true
        guard (ends.values.max() ?? 0) > 0 else { throw MeetingError.noAudio }
        return draft
    }
}

public enum MeetingAudioStore {
    static func ensureDirectory(_ url: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            guard try fm.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType == .typeDirectory else { throw MeetingError.storage }
        } else { try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
    }
    static func regular(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.referenceCount] as? NSNumber)?.intValue == 1 else { throw MeetingError.storage }
    }
    static func save(_ draft: MeetingDraft, in folder: URL) throws {
        let url = folder.appendingPathComponent("session.json")
        try JSONEncoder().encode(draft).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public static func drafts(in directory: URL) throws -> [MeetingDraft] { try scanDrafts(in: directory).drafts }
    public static func scanDrafts(in directory: URL) throws -> (drafts: [MeetingDraft], unreadable: Int) {
        let root = directory.appendingPathComponent("MeetingStaging")
        guard FileManager.default.fileExists(atPath: root.path) else { return ([], 0) }
        try ensureDirectory(root)
        var drafts: [MeetingDraft] = []; var unreadable = 0
        for folder in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where UUID(uuidString: folder.lastPathComponent) != nil {
            do {
                try ensureDirectory(folder)
                let url = folder.appendingPathComponent("session.json"); try regular(url)
                let draft = try JSONDecoder().decode(MeetingDraft.self, from: Data(contentsOf: url))
                guard draft.id == folder.lastPathComponent else { throw MeetingError.storage }
                drafts.append(draft)
            } catch { unreadable += 1 }
        }
        return (drafts.sorted { $0.createdAt < $1.createdAt }, unreadable)
    }
    /// Left channel is microphone, right channel is app audio. ASR downmixes a bounded read.
    public static func recover(_ draft: MeetingDraft, directory: URL, history: HistoryStore, interrupted: Bool) throws -> RecordingAsset {
        guard UUID(uuidString: draft.id) != nil else { throw MeetingError.storage }
        let root = directory.appendingPathComponent("MeetingStaging")
        try ensureDirectory(root)
        let folder = root.appendingPathComponent(draft.id); try ensureDirectory(folder)
        // A crash after the SQL commit must not duplicate the recording on recovery.
        if let existing = try history.recording(id: draft.id) {
            guard existing.source == .meeting, history.audioURL(for: existing) != nil else { throw MeetingError.storage }
            try FileManager.default.removeItem(at: folder)
            return existing
        }
        let tracks = try MeetingTrack.allCases.map { track -> (FileHandle, Int) in
            let url = folder.appendingPathComponent(track.rawValue + ".pcm"); try regular(url)
            let bytes = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
            let count = (bytes?.intValue ?? 0) / 2
            guard count <= Int(MediaConfiguration.maximumDuration * 16_000) else { throw MediaError.tooLong }
            return (try FileHandle(forReadingFrom: url), count)
        }
        defer { for (handle, _) in tracks { try? handle.close() } }
        let length = tracks.map(\.1).max() ?? 0
        guard length > 0 else { throw MeetingError.noAudio }
        let output = folder.appendingPathComponent("complete.wav")
        if FileManager.default.fileExists(atPath: output.path) { try regular(output); try FileManager.default.removeItem(at: output) }
        do {
            let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 2)!
            let file = try AVAudioFile(forWriting: output, settings: [AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false], commonFormat: .pcmFormatFloat32, interleaved: false)
            for offset in stride(from: 0, to: length, by: 16_000) {
                let count = min(16_000, length - offset)
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
                buffer.frameLength = AVAudioFrameCount(count)
                for (channel, pair) in tracks.enumerated() {
                    let data = try pair.0.read(upToCount: count * 2) ?? Data()
                    let pointer = buffer.floatChannelData![channel]
                    pointer.initialize(repeating: 0, count: count)
                    data.withUnsafeBytes { bytes in
                        for i in 0..<(data.count / 2) { pointer[i] = Float(Int16(littleEndian: bytes.loadUnaligned(fromByteOffset: i * 2, as: Int16.self))) / 32768 }
                    }
                }
                try file.write(from: buffer)
            }
        } // Close WAV before publishing its asset.
        var notes = draft.interruptions
        if interrupted { notes.insert("Recovered after recording was interrupted; the final audio may be incomplete.", at: 0) }
        if tracks[1].1 == 0 { notes.append("No app audio was received.") }
        if draft.microphone && tracks[0].1 == 0 { notes.append("No microphone audio was received.") }
        let asset = try history.importRecording(from: output, source: .meeting, recordingID: draft.id,
            captureIssue: notes.isEmpty ? nil : Array(Set(notes)).sorted().joined(separator: " "), createdAt: draft.createdAt)
        try FileManager.default.removeItem(at: folder)
        return asset
    }
    public static func discardEmpty(id: String, directory: URL) throws {
        guard UUID(uuidString: id) != nil else { throw MeetingError.storage }
        let root = directory.appendingPathComponent("MeetingStaging"); try ensureDirectory(root)
        let folder = root.appendingPathComponent(id); try ensureDirectory(folder)
        for track in MeetingTrack.allCases {
            let url = folder.appendingPathComponent(track.rawValue + ".pcm"); try regular(url)
            guard (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue == 0 else { return }
        }
        try FileManager.default.removeItem(at: folder)
    }
    public static func removeDrafts(in directory: URL) throws {
        let root = directory.appendingPathComponent("MeetingStaging")
        if FileManager.default.fileExists(atPath: root.path) { try ensureDirectory(root); try FileManager.default.removeItem(at: root) }
    }
}
