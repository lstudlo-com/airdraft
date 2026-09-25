import AirdraftCore
import Foundation

/// Prepared once per database result, never from a scrolling view's body.
struct HistorySnapshot: Sendable {
    let entries: [HistoryEntry]
    let indexByID: [Int64: Int]
    static let empty = HistorySnapshot(entries: [], indexByID: [:])

    static func prepare(_ records: [DictationRecord], history: HistoryStore, appendingTo previous: Self = .empty,
                        calendar: Calendar = .current, now: Date = Date()) -> Self {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        var previousDay = previous.entries.last.map { calendar.startOfDay(for: $0.record.createdAt) }
        var entries = previous.entries
        var indexByID = previous.indexByID
        entries.reserveCapacity(entries.count + records.count)
        indexByID.reserveCapacity(indexByID.count + records.count)
        for record in records {
            guard let id = record.id, indexByID[id] == nil else { continue }
            let day = calendar.startOfDay(for: record.createdAt)
            let heading: String?
            if day == previousDay { heading = nil }
            else if day == today { heading = "Today" }
            else if day == yesterday { heading = "Yesterday" }
            else { heading = record.createdAt.formatted(date: .abbreviated, time: .omitted) }
            let time = record.createdAt.formatted(date: .omitted, time: .shortened)
            var metadata = [time]
            if let app = record.appName { metadata.append(app) }
            if record.outputDestination == TextOutputDestination.script.rawValue {
                metadata.append(record.outputSucceeded == true ? "Sent to script" : "Script failed")
            }
            metadata += [record.mode, "\(String(format: "%.0f", record.audioSeconds)) s"]
            let finalText = HistoryTextContent(record.finalText)
            indexByID[id] = entries.count
            entries.append(HistoryEntry(id: id, record: record, heading: heading,
                timelineHeading: heading.map {
                    $0 == "Today" || $0 == "Yesterday" ? $0 : record.createdAt.formatted(.dateTime.month(.abbreviated).day())
                }, time: time, timestamp: record.createdAt.formatted(date: .abbreviated, time: .standard),
                metadata: metadata.joined(separator: " · "),
                finalText: finalText, rawText: record.rawTranscript == record.finalText ? finalText : HistoryTextContent(record.rawTranscript),
                audioAvailable: history.audioURL(for: record) != nil))
            previousDay = day
        }
        return Self(entries: entries, indexByID: indexByID)
    }

    /// Visibility contains only the small on-screen set; never scan the history.
    func firstVisibleID(in ids: [Int64]) -> Int64? {
        ids.compactMap { id in indexByID[id].map { (id, $0) } }.min { $0.1 < $1.1 }?.0
    }
}

struct HistoryEntry: Identifiable, Sendable {
    let id: Int64
    let record: DictationRecord
    let heading: String?
    let timelineHeading: String?
    let time: String
    let timestamp: String
    let metadata: String
    let finalText: HistoryTextContent
    let rawText: HistoryTextContent
    let audioAvailable: Bool
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
