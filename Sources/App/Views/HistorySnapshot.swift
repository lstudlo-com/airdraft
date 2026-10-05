import AirdraftCore
import Foundation

/// Prepared once per database result, never from a scrolling view's body.
struct HistorySnapshot: Sendable {
    let entries: [HistoryEntry]
    let indexByID: [String: Int]
    static let empty = HistorySnapshot(entries: [], indexByID: [:])

    static func prepare(_ records: [DictationRecord], history: HistoryStore, appendingTo previous: Self = .empty,
                        calendar: Calendar = .current, now: Date = Date()) -> Self {
        let items = records.compactMap { record -> Item? in
            guard let id = record.id else { return nil }
            let asset = record.recordingID.flatMap { try? history.recording(id: $0) }
            let available = asset.flatMap { history.audioURL(for: $0) == nil ? nil : $0 }
            return Item(id: String(id), date: record.createdAt, record: record, asset: available)
        }
        return prepare(items, appendingTo: previous, calendar: calendar, now: now)
    }

    static func prepareItems(_ items: [HistoryItem], appendingTo previous: Self = .empty) -> Self {
        prepare(items.compactMap { item in
            if let record = item.dictation, let id = record.id {
                return Item(id: String(id), date: record.createdAt, record: record, asset: item.asset)
            }
            if let document = item.document {
                return Item(id: "document:" + document.id, date: document.createdAt, record: nil, asset: item.asset, document: document)
            }
            return nil
        }, appendingTo: previous, calendar: .current, now: Date())
    }

    static func prepareRecordings(_ recordings: [RecordingPage.Entry], appendingTo previous: Self = .empty,
                                  calendar: Calendar = .current, now: Date = Date()) -> Self {
        prepare(recordings.map { Item(id: "recording:" + $0.id, date: $0.asset.createdAt, record: $0.dictation, asset: $0.asset, document: $0.document) },
                appendingTo: previous, calendar: calendar, now: now)
    }

    private struct Item {
        let id: String
        let date: Date
        let record: DictationRecord?
        let asset: RecordingAsset?
        var document: TranscriptDocument? = nil
    }

    private static func prepare(_ items: [Item], appendingTo previous: Self, calendar: Calendar, now: Date) -> Self {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        var previousDay = previous.entries.last.map { calendar.startOfDay(for: $0.createdAt) }
        var entries = previous.entries
        var indexByID = previous.indexByID
        entries.reserveCapacity(entries.count + items.count)
        indexByID.reserveCapacity(indexByID.count + items.count)
        for item in items {
            guard indexByID[item.id] == nil else { continue }
            let day = calendar.startOfDay(for: item.date)
            let heading: String?
            if day == previousDay { heading = nil }
            else if day == today { heading = "Today" }
            else if day == yesterday { heading = "Yesterday" }
            else { heading = item.date.formatted(date: .abbreviated, time: .omitted) }
            let time = item.date.formatted(date: .omitted, time: .shortened)
            var metadata = [time]
            if let record = item.record {
                if let app = record.appName { metadata.append(app) }
                if record.outputDestination == TextOutputDestination.script.rawValue {
                    metadata.append(record.outputSucceeded == true ? "Sent to script" : "Script failed")
                }
                metadata += [record.mode, "\(String(format: "%.0f", record.audioSeconds)) s"]
            }
            let finalText = HistoryTextContent(item.document?.text ?? item.record?.finalText ?? "")
            indexByID[item.id] = entries.count
            entries.append(HistoryEntry(id: item.id, createdAt: item.date, record: item.record, asset: item.asset, heading: heading,
                timelineHeading: heading.map { _ in item.date.formatted(.dateTime.month(.abbreviated).day()) },
                time: time, timestamp: item.date.formatted(date: .abbreviated, time: .standard),
                metadata: metadata.joined(separator: " · "), finalText: finalText,
                rawText: item.record?.rawTranscript == item.record?.finalText ? finalText : HistoryTextContent(item.record?.rawTranscript ?? ""), document: item.document))
            previousDay = day
        }
        return Self(entries: entries, indexByID: indexByID)
    }

    /// Visibility contains only the small on-screen set; never scan the history.
    func firstVisibleID(in ids: [String]) -> String? {
        ids.compactMap { id in indexByID[id].map { (id, $0) } }.min { $0.1 < $1.1 }?.0
    }
}

struct HistoryEntry: Identifiable, Sendable {
    let id: String
    let createdAt: Date
    let record: DictationRecord?
    let asset: RecordingAsset?
    let heading: String?
    let timelineHeading: String?
    let time: String
    let timestamp: String
    let metadata: String
    let finalText: HistoryTextContent
    let rawText: HistoryTextContent
    var document: TranscriptDocument? = nil
    var audioAvailable: Bool { asset != nil }
}

struct HistoryTextContent: Equatable, Sendable {
    let full: String
    let preview: String
    let hasOmittedTail: Bool

    init(_ text: String) {
        full = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Bound collapsed shaping even for multi-hour transcripts. Split only at
        // grapheme boundaries; Copy, Original and expansion still use the full text.
        let end = full.index(full.startIndex, offsetBy: 2048, limitedBy: full.endIndex) ?? full.endIndex
        hasOmittedTail = end != full.endIndex
        preview = hasOmittedTail ? String(full[..<end]) : full
    }
}
