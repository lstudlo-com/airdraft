#if DEBUG
import AirdraftCore
import Foundation

@MainActor enum MediaPreview {
    static var document: TranscriptDocument {
        var value = TranscriptDocument(recordingID: "fixture", title: "Product planning · Wednesday", configuration: .init())
        value.words = [
            .init(start: 0.5, end: 4.2, text: "Let's review the two priorities for the next release. ", speaker: "1"),
            .init(start: 4.5, end: 9.8, text: "先完成錄音保存，再加入分人逐字稿。我們也要保留原始文字。", speaker: "2"),
            .init(start: 10.2, end: 14.6, text: "Agreed. The transcript should remain available even when speaker detection fails.", speaker: "1"),
            .init(start: 14.7, end: 18.5, text: "Yes, and retries should resume from the last saved stage.", speaker: "2", overlapping: true)
        ]
        value.speakerNames = ["1": "Alex", "2": "Jamie"]
        value.transcriptionComplete = true; value.diarizationComplete = true; value.stage = .completed
        value.rebuildTurns()
        return value
    }
    static func seed(_ history: HistoryStore) throws {
        let asset = try history.saveRecording(samples: Array(repeating: 0, count: 20 * 16_000), source: .imported)
        var saved = try history.createDocument(asset: asset, title: document.title, configuration: document.configuration)
        saved.words = document.words; saved.turns = document.turns; saved.speakerNames = document.speakerNames
        saved.stage = .completed; saved.transcriptionComplete = true; saved.diarizationComplete = true
        _ = try history.updateDocument(saved)
    }
    static func seedMeetings(_ history: HistoryStore) throws {
        let now = Date()
        let latest = try history.saveRecording(samples: Array(repeating: 0, count: 32_000), source: .meeting, createdAt: now)
        _ = latest
        let older = try history.saveRecording(samples: Array(repeating: 0, count: 20 * 16_000), source: .meeting,
                                             createdAt: now.addingTimeInterval(-86_400))
        for title in ["Planning review · Original", "Planning review"] {
            var saved = try history.createDocument(asset: older, title: title, configuration: .init(language: "en", localModel: .qwenSmall))
            saved.words = document.words; saved.turns = document.turns; saved.speakerNames = document.speakerNames
            saved.stage = .completed; saved.transcriptionComplete = true; saved.diarizationComplete = true
            _ = try history.updateDocument(saved)
        }
        _ = try history.saveRecording(samples: Array(repeating: 0, count: 4 * 16_000), source: .meeting,
                                      createdAt: now.addingTimeInterval(-2 * 86_400))
    }
}
#endif
