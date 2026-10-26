import XCTest
import GRDB
@testable import AirdraftCore

/// AD-086: speaker-name suggestions across meetings and summary templates.
/// Disposable stores, injected refiners; no network, audio devices or daily data.
final class MeetingSpeakerSummaryTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Airdraft-SpeakerSummary-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func completedDocument(_ history: HistoryStore) throws -> TranscriptDocument {
        let asset = try history.saveRecording(samples: Array(repeating: 0, count: 16_000), source: .meeting)
        var document = try history.createDocument(asset: asset, title: "Weekly sync", configuration: .init())
        document.words = [
            .init(start: 0, end: 1, text: "We ship on Friday. ", speaker: "1"),
            .init(start: 1.2, end: 2, text: "I will write the notes. ", speaker: "2"),
            .init(start: 4, end: 5, text: "Then the beta opens. ", speaker: "1")
        ]
        document.rebuildTurns(); document.stage = .completed
        document.transcriptionComplete = true; document.diarizationComplete = true
        return try history.updateDocument(document)
    }

    // MARK: Library

    /// The library stores names only, deduplicates keeping the newest spelling ordered by
    /// last use, persists bounded across reopen, and is removed by text cleanup and reset
    /// but kept by audio-only cleanup.
    func testLibraryStoresBoundedDeduplicatedNamesAndFollowsCleanupScopes() throws {
        do { // LibraryStoresNamesOnlyAndRejectsPassagesAndDefaultLabels
            let history = try HistoryStore(directory: try directory())
            let long = String(repeating: "x", count: SpeakerNameLibrary.maximumNameLength + 1)
            try history.rememberSpeakerNames(["  Alex   Chen ", "Speaker 2", TranscriptDocument.defaultSpeakerName("3"),
                                              TranscriptDocument.unknownSpeakerName, "", "two\nlines", long, "林語晴"],
                                             at: Date(timeIntervalSince1970: 10))
            XCTAssertEqual(Set(try history.recentSpeakerNames()), ["Alex Chen", "林語晴"])
            // The schema itself has no room for transcripts, documents, speaker IDs or embeddings.
            let columns = try history.dbQueue.read { db in try db.columns(in: "speakerName").map(\.name) }
            XCTAssertEqual(Set(columns), ["key", "name", "lastUsedAt"])
        }

        do { // LibraryDeduplicatesKeepsNewestSpellingAndOrdersByLastUse
            let history = try HistoryStore(directory: try directory())
            try history.rememberSpeakerNames(["Alex", "Jamie"], at: Date(timeIntervalSince1970: 10))
            try history.rememberSpeakerNames(["Morgan"], at: Date(timeIntervalSince1970: 20))
            try history.rememberSpeakerNames(["ALEX"], at: Date(timeIntervalSince1970: 30))
            XCTAssertEqual(try history.recentSpeakerNames(), ["ALEX", "Morgan", "Jamie"])
            XCTAssertEqual(try history.recentSpeakerNames(limit: 1), ["ALEX"])
            XCTAssertEqual(try history.speakerNameCount(), 3)
        }

        do { // LibraryPersistsAcrossReopenAndStaysBounded
            let root = try directory()
            do {
                let history = try HistoryStore(directory: root)
                for index in 0..<(SpeakerNameLibrary.capacity + 5) {
                    try history.rememberSpeakerNames(["Person \(index)"], at: Date(timeIntervalSince1970: Double(index)))
                }
                try history.close()
            }
            let reopened = try HistoryStore(directory: root)
            XCTAssertEqual(try reopened.speakerNameCount(), SpeakerNameLibrary.capacity)
            XCTAssertEqual(try reopened.recentSpeakerNames(limit: 2), ["Person \(SpeakerNameLibrary.capacity + 4)", "Person \(SpeakerNameLibrary.capacity + 3)"])
            XCTAssertFalse(try reopened.recentSpeakerNames(limit: 500).contains("Person 0"))
        }

        do { // TextCleanupScopesAndResetRemoveLibraryButAudioCleanupKeepsIt
            let root = try directory()
            let history = try HistoryStore(directory: root)
            try history.rememberSpeakerNames(["Alex"])
            try history.deleteAllAudio()
            XCTAssertEqual(try history.recentSpeakerNames(), ["Alex"], "Audio-only cleanup keeps text-derived names")
            try history.deleteHistoryKeepingAudio()
            XCTAssertEqual(try history.speakerNameCount(), 0)
            try history.rememberSpeakerNames(["Jamie"])
            try history.deleteAll()
            XCTAssertEqual(try history.speakerNameCount(), 0)
            try history.rememberSpeakerNames(["Morgan"])
            try history.forgetSpeakerNames()
            XCTAssertEqual(try history.speakerNameCount(), 0)
            // Reset removes the database file that holds the library.
            try history.rememberSpeakerNames(["Priya"])
            try history.close()
            try ManagedDataFiles.resetContents(in: root)
            XCTAssertEqual(try HistoryStore(directory: root).speakerNameCount(), 0)
        }
    }

    // MARK: Renaming

    func testRenameAppliesToEverySegmentAndSuggestionsSkipDefaultsAndTakenNames() throws {
        do { // RenameAppliesToEverySegmentOfThatSpeakerAndPreservesOriginals
            let history = try HistoryStore(directory: try directory())
            var document = try completedDocument(history)
            XCTAssertEqual(document.turns.filter { $0.speaker == "1" }.count, 2)
            let stale = document
            document.setSpeakerName("Alex", for: "1")
            document = try history.updateDocument(document)
            let saved = try XCTUnwrap(history.document(id: document.id))
            for turn in saved.turns where turn.speaker == "1" { XCTAssertEqual(saved.speakerName(turn.speaker), "Alex") }
            XCTAssertEqual(saved.speakerName("2"), "Speaker 2")
            // Original words and speaker assignments remain intact.
            XCTAssertEqual(saved.words.map(\.speaker), ["1", "2", "1"])
            XCTAssertEqual(saved.turns.map(\.originalSpeaker), ["1", "2", "1"])
            XCTAssertTrue(saved.turns.allSatisfy { $0.editedText == nil })
            let text = String(decoding: try TranscriptExport.data(saved, format: .txt), as: UTF8.self)
            XCTAssertEqual(text.components(separatedBy: "Alex:").count - 1, 2)
            let original = String(decoding: try TranscriptExport.data(saved, format: .txt, original: true), as: UTF8.self)
            XCTAssertEqual(original.components(separatedBy: "Alex:").count - 1, 2, "Names are shared between versions")
            // A cleared name shows the label instead of an empty speaker.
            var cleared = saved
            cleared.setSpeakerName("  ", for: "1")
            XCTAssertEqual(cleared.speakerName("1"), "Speaker 1")
            XCTAssertThrowsError(try history.updateDocument(stale), "Stale revisions cannot overwrite the saved names")
        }

        do { // RememberableNamesAndSuggestionsSkipDefaultsAndNamesTakenByOtherSpeakers
            var document = TranscriptDocument(recordingID: "fixture", title: "Sync", configuration: .init())
            document.speakerNames = ["1": "Alex", "2": TranscriptDocument.defaultSpeakerName("2"), "3": " alex ", "4": "Jamie"]
            XCTAssertEqual(document.rememberableSpeakerNames, ["Alex", "Jamie"])
            XCTAssertEqual(document.speakerNameSuggestions(["Morgan", "ALEX", "Jamie"], for: "2"), ["Morgan"])
            XCTAssertEqual(document.speakerNameSuggestions(["Morgan", "Jamie"], for: "4"), ["Morgan", "Jamie"])
        }
    }

    // MARK: Templates

    @MainActor func testTemplateChoicePersistsAndLegacyValuesFallBackOrDecode() throws {
        do { // TemplateChoicePersistsPerUserAndFallsBackForUnknownValues
            let name = "airdraft.tests.summary.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            XCTAssertEqual(AppSettings(defaults: defaults).meetingSummaryTemplate, .brief)
            AppSettings(defaults: defaults).meetingSummaryTemplate = .minutes
            XCTAssertEqual(AppSettings(defaults: defaults).meetingSummaryTemplate, .minutes)
            defaults.set(Data("\"retired\"".utf8), forKey: "settings.meetingSummaryTemplate")
            XCTAssertEqual(AppSettings(defaults: defaults).meetingSummaryTemplate, .default)
        }

        do { // LegacyDocumentPayloadWithoutTemplateStillDecodes
            var document = TranscriptDocument(recordingID: "fixture", title: "Old", configuration: .init())
            document.summary = "Old summary"
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
            json.removeValue(forKey: "summaryTemplate")
            let decoded = try JSONDecoder().decode(TranscriptDocument.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertEqual(decoded.summary, "Old summary"); XCTAssertNil(decoded.summaryTemplate)
        }
    }

    func testPromptAssemblyPerTemplateAndBoundedSectionsMatchingCharacterSplit() throws {
        do { // PromptAssemblyIsEnglishPerTemplateAndAsksForTranscriptLanguage
            var document = TranscriptDocument(recordingID: "fixture", title: "Sync", configuration: .init())
            document.words = [.init(start: 0, end: 1, text: "我們週五上線。", speaker: "1"), .init(start: 2, end: 3, text: "OK.", speaker: "2")]
            document.rebuildTurns(); document.speakerNames = ["1": "林語晴"]
            var systems: Set<String> = []
            for template in MeetingSummaryTemplate.allCases {
                let requests = MeetingSummaryPrompt.requests(for: document, template: template)
                XCTAssertEqual(requests.count, 1)
                let request = try XCTUnwrap(requests.first)
                let system = PromptBuilder.systemPrompt(for: request)
                XCTAssertTrue(system.hasPrefix("TASK: " + template.task), "\(template)")
                XCTAssertTrue(system.contains(template.shape))
                XCTAssertTrue(system.contains("Write in the language or languages used in the transcript"))
                XCTAssertTrue(system.contains(MeetingSummaryPrompt.baseRules))
                XCTAssertFalse(system.contains("You are a dictation post-processor"), "Summaries use their own base rules")
                XCTAssertTrue(system.allSatisfy(\.isASCII), "Prompts are never localized")
                XCTAssertTrue(PromptBuilder.userMessage(for: request).contains("林語晴: 我們週五上線。\nSpeaker 2: OK."))
                systems.insert(system)
            }
            XCTAssertEqual(systems.count, MeetingSummaryTemplate.allCases.count, "Each template has its own prompt")
        }

        do { // SectionsStayBoundedAndSplitLongEdits
            var document = TranscriptDocument(recordingID: "fixture", title: "Long", configuration: .init())
            document.words = (0..<40).map { .init(start: Double($0) * 2, end: Double($0) * 2 + 1, text: String(repeating: "a", count: 500), speaker: $0 % 2 == 0 ? "1" : "2") }
            document.rebuildTurns()
            document.turns[0].editedText = String(repeating: "b", count: 20_000)
            let sections = MeetingSummaryPrompt.sections(for: document)
            XCTAssertGreaterThan(sections.count, 3)
            XCTAssertTrue(sections.allSatisfy { $0.count <= MeetingSummaryPrompt.sectionCharacterLimit })
            XCTAssertEqual(sections.joined().filter { $0 == "b" }.count, 20_000)
        }

        // The tracked-length split must match the original character-by-character
        // split exactly, and stay fast for a long CJK meeting (review #5).
        do { // SectionsMatchCharacterSplitAndStayFast
            func reference(_ document: TranscriptDocument, limit: Int) -> [String] {
                var chunks: [String] = []; var current = ""
                for turn in document.turns {
                    let line = document.speakerName(turn.speaker) + ": " + turn.text + "\n"
                    if current.count + line.count > limit, !current.isEmpty { chunks.append(current); current = "" }
                    for character in line {
                        current.append(character)
                        if current.count >= limit { chunks.append(current); current = "" }
                    }
                }
                if !current.isEmpty { chunks.append(current) }
                return chunks
            }
            for (count, length) in [(3, 10), (40, 37), (25, 199), (12, 1_000)] {
                var document = TranscriptDocument(recordingID: "fixture", title: "Split", configuration: .init())
                document.words = (0..<count).map { .init(start: Double($0) * 2, end: Double($0) * 2 + 1,
                    text: String(repeating: $0 % 3 == 0 ? "會" : "a", count: length + $0), speaker: $0 % 2 == 0 ? "1" : "2") }
                document.rebuildTurns()
                for limit in [50, 200, 1_000] {
                    XCTAssertEqual(MeetingSummaryPrompt.sections(for: document, limit: limit), reference(document, limit: limit),
                                   "\(count)×\(length) at \(limit)")
                }
            }
            var long = TranscriptDocument(recordingID: "fixture", title: "Long", configuration: .init())
            long.words = (0..<300).map { .init(start: Double($0) * 2, end: Double($0) * 2 + 1,
                text: String(repeating: "我們週五上線", count: 80), speaker: $0 % 2 == 0 ? "1" : "2") }
            long.rebuildTurns()
            let started = ContinuousClock.now
            let sections = MeetingSummaryPrompt.sections(for: long)
            XCTAssertLessThan(started.duration(to: .now), .seconds(1), "About 150,000 characters must split quickly")
            XCTAssertEqual(sections.joined().count, long.turns.map { long.speakerName($0.speaker).count + 2 + $0.text.count + 1 }.reduce(0, +))
        }
    }

    // MARK: Runner

    private struct FakeRefiner: Refiner {
        let id = "fake"
        let requests: Locked<[RefineRequest]>
        let reply: @Sendable (Int) throws -> String
        func prewarmPrompt(_ request: RefineRequest, backend: RefinementPreparationBackend) async throws {}
        func refine(_ request: RefineRequest) async throws -> RefineResult {
            let index = requests.withLock { $0.append(request); return $0.count - 1 }
            return RefineResult(text: try reply(index), engine: id, latencyMs: 1, promptVersion: "test")
        }
    }

    @MainActor private func runner(_ history: HistoryStore, root: URL, refiner: FakeRefiner) -> MediaJobRunner {
        MediaJobRunner(history: history, directory: root, factory: EngineFactory(status: EngineStatus(), credentialReader: { _ in nil }),
                       credentialReader: { _ in nil }, refinerProvider: { _ in refiner })
    }

    @MainActor func testSummarizeRecordsSelectedTemplateAndFailedOrEmptyResultKeepsEarlierSummary() async throws {
        do { // SummarizeUsesSelectedTemplateThroughInjectedRefinerAndRecordsIt
            let root = try directory(); let history = try HistoryStore(directory: root)
            var document = try completedDocument(history)
            document.setSpeakerName("Alex", for: "1"); document = try history.updateDocument(document)
            let requests = Locked<[RefineRequest]>([])
            let media = runner(history, root: root, refiner: FakeRefiner(requests: requests, reply: { _ in "  - Alex: ship on Friday\n" }))
            media.summarize(id: document.id, configuration: LLMConfig(), template: .actionItems)
            while media.isBusy { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertNil(media.issue)
            let saved = try XCTUnwrap(history.document(id: document.id))
            XCTAssertEqual(saved.summary, "- Alex: ship on Friday")
            XCTAssertEqual(saved.summaryTemplate, .actionItems)
            XCTAssertEqual(saved.turns, document.turns, "The transcript is unchanged")
            let sent = requests.value
            XCTAssertEqual(sent.count, 1)
            XCTAssertEqual(sent.first?.profile.task, MeetingSummaryTemplate.actionItems.profile.task)
            XCTAssertTrue(sent.first?.transcript.contains("Alex: We ship on Friday.") == true)
        }

        do { // FailedOrEmptySummaryKeepsTranscriptAndEarlierSummary
            let root = try directory(); let history = try HistoryStore(directory: root)
            var document = try completedDocument(history)
            document.summary = "Earlier summary"; document.summaryTemplate = .brief
            document = try history.updateDocument(document)
            struct Offline: Error {}
            let replies: [@Sendable (Int) throws -> String] = [{ _ in throw Offline() }, { _ in "  \n" }]
            for reply in replies {
                let media = runner(history, root: root, refiner: FakeRefiner(requests: Locked<[RefineRequest]>([]), reply: reply))
                media.summarize(id: document.id, configuration: LLMConfig(), template: .minutes)
                while media.isBusy { try await Task.sleep(for: .milliseconds(10)) }
                XCTAssertNotNil(media.issue)
                let saved = try XCTUnwrap(history.document(id: document.id))
                XCTAssertEqual(saved.summary, "Earlier summary"); XCTAssertEqual(saved.summaryTemplate, .brief)
                XCTAssertEqual(saved.turns, document.turns); XCTAssertEqual(saved.revision, document.revision)
            }
        }
    }
}
