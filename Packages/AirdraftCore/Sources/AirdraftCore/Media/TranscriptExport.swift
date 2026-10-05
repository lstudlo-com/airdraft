import Foundation

public enum TranscriptExport {
    public enum Format: String, CaseIterable { case txt, json, srt, vtt }
    public static func data(_ source: TranscriptDocument, format: Format, original: Bool = false) throws -> Data {
        var document = source
        if original {
            for index in document.turns.indices {
                document.turns[index].editedText = nil
                document.turns[index].speaker = document.turns[index].originalSpeaker
            }
            document.summary = nil
        }
        if format == .json {
            struct Export: Encodable {
                let title: String
                let createdAt: Date
                let originalWords: [TranscriptWord]
                let turns: [TranscriptTurn]
                let speakers: [String: String]
                let summary: String?
            }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(Export(title: document.title, createdAt: document.createdAt,
                originalWords: document.words, turns: document.turns, speakers: document.speakerNames, summary: document.summary))
        }
        if format == .txt {
            let text = document.turns.map { "[\(timestamp($0.start, decimal: "."))] \(document.speakerName($0.speaker)): \($0.text.trimmingCharacters(in: .whitespacesAndNewlines))" }.joined(separator: "\n\n")
            return Data((document.title + "\n\n" + text).utf8)
        }
        let separator = format == .srt ? "," : "."
        var result = format == .vtt ? "WEBVTT\n\n" : ""
        for (index, turn) in document.turns.enumerated() {
            result += "\(index + 1)\n\(timestamp(turn.start, decimal: separator)) --> \(timestamp(max(turn.end, turn.start + 0.001), decimal: separator))\n"
            let text = (document.speakerName(turn.speaker) + ": " + turn.text).replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
            result += (format == .vtt ? text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") : text) + "\n\n"
        }
        return Data(result.utf8)
    }
    private static func timestamp(_ seconds: Double, decimal: String) -> String {
        let milliseconds = Int((max(0, seconds.isFinite ? seconds : 0) * 1000).rounded())
        return String(format: "%02d:%02d:%02d%@%03d", milliseconds / 3_600_000, milliseconds / 60_000 % 60,
                      milliseconds / 1000 % 60, decimal, milliseconds % 1000)
    }
}
