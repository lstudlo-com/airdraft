import XCTest
import AVFoundation
@testable import AirdraftCore

@MainActor
final class MeetingWorkflowTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("airdraft-meeting-flow-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func factory(_ speech: SegmentSpeech) -> EngineFactory {
        EngineFactory(status: EngineStatus(), credentialReader: { _ in nil }, transcriberBuilder: { _ in speech })
    }
    private func wait(_ runner: MediaJobRunner, seconds: Double = 10) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while runner.isBusy && Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(runner.isBusy, "Job did not finish: \(runner.activity)")
        if runner.isBusy { runner.cancel(); throw MediaError.busy }
    }

    func testLegacyPayloadAndEveryLocalModelRetainTheirConfiguration() throws {
        let old = Data(#"{"engine":"local","whisperModel":"large-v3-v20240930_turbo","language":"zh","identifySpeakers":true}"#.utf8)
        let legacy = try JSONDecoder().decode(MediaConfiguration.self, from: old)
        XCTAssertEqual(legacy.selectedLocalModel, .whisperTurbo)
        XCTAssertEqual(legacy.asr.kind, .whisperKit)
        XCTAssertNoThrow(try legacy.validate())
        for model in MediaConfiguration.LocalModel.allCases {
            let config = MediaConfiguration(language: model == .apple ? "" : "en", localModel: model, appleLocale: "en-US")
            XCTAssertNoThrow(try config.validate(), model.title)
            let saved = try JSONDecoder().decode(MediaConfiguration.self, from: JSONEncoder().encode(config))
            XCTAssertEqual(saved, config)
            XCTAssertEqual(saved.asr.kind, model.kind)
            XCTAssertNotNil(SpeechLanguagePolicy.capabilities(for: saved.asr).supportsAutomatic)
        }
        XCTAssertThrowsError(try MediaConfiguration(language: "zh", localModel: .parakeet).validate())
        XCTAssertThrowsError(try MediaConfiguration(language: "", localModel: .cohere).validate())
        XCTAssertEqual(MediaConfiguration(localModel: .qwenSmall).asr.qwen3Model, "aufklarer/Qwen3-ASR-0.6B-MLX-4bit")
        var switched = MediaConfiguration(language: "en", localModel: .qwenSmall)
        switched.selectLocalModel(.apple)
        XCTAssertEqual(switched.language, "")
        XCTAssertEqual(switched.appleLocale, "en-US")
        XCTAssertEqual(switched.asr.effectiveAppleLocale, switched.appleLocale)
        var document = TranscriptDocument(recordingID: "legacy", title: "Legacy", configuration: legacy)
        document.words = [.init(start: 0, end: 1, text: "old")]
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
        payload.removeValue(forKey: "speakerIntervals")
        let decoded = try JSONDecoder().decode(TranscriptDocument.self, from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertEqual(decoded.words.first?.text, "old")
        XCTAssertNil(decoded.speakerIntervals)
    }

    func testSegmentPlanCoversQuickTurnsOverlapGapsAndFinalFrameExactlyOnce() {
        let duration = 61 + 1.0 / 16_000
        let plan = MediaSegmentPlan.make(duration: duration, speakers: [
            .init(start: -.infinity, end: 2, speaker: "bad"),
            .init(start: 2, end: .nan, speaker: "bad"),
            .init(start: -1, end: 0.4, speaker: "A"),
            .init(start: 0.4, end: 0.9, speaker: "B"),
            .init(start: 0.9, end: 2, speaker: "A"),
            .init(start: 1.5, end: 3, speaker: "B"),
            .init(start: 5, end: 90, speaker: "A")])
        XCTAssertEqual(plan.first?.startFrame, 0)
        XCTAssertEqual(plan.last?.endFrame, 976_001)
        XCTAssertEqual(plan.map { $0.endFrame - $0.startFrame }.reduce(0, +), 976_001)
        for (left, right) in zip(plan, plan.dropFirst()) { XCTAssertEqual(left.endFrame, right.startFrame) }
        XCTAssertTrue(plan.allSatisfy { $0.endFrame > $0.startFrame && $0.endFrame - $0.startFrame <= 400_000 })
        XCTAssertEqual(plan.prefix(3).map(\.speaker), ["A", "B", "A"])
        XCTAssertTrue(plan.contains { $0.start == 1.5 && $0.end == 2 && $0.overlapping && $0.speaker == nil })
        XCTAssertTrue(plan.contains { $0.start == 3 && $0.end == 5 && !$0.overlapping && $0.speaker == nil })
        XCTAssertEqual(MediaSegmentPlan.make(duration: 1, speakers: []).first?.speaker, nil)
    }

    func testActualFactoryRoutesAllAddedLocalEnginesWithHonestSegmentBounds() async throws {
        for model in MediaConfiguration.LocalModel.allCases where model != .whisperTurbo {
            let config = MediaConfiguration(language: model == .apple ? "" : "en", localModel: model, appleLocale: "en-US")
            let speech = SegmentSpeech(ready: true)
            let engine = factory(speech)
            let words = try await engine.transcribeMediaWindow(Array(repeating: 0.1, count: 8_000), offset: 12.25, config: config.asr)
            XCTAssertEqual(words.count, 1, model.title)
            XCTAssertEqual(words.first?.start, 12.25)
            XCTAssertEqual(words.first?.end, 12.75)
            XCTAssertEqual(words.first?.timing, .segment)
            XCTAssertEqual(words.first?.text, "segment1 ")
            await engine.unloadAll()
        }
    }

    func testSpeechTurnsPreserveContextShortTurnsAndUnknownActivity() {
        let turns = MediaSegmentPlan.speechTurns(duration: 12, speakers: [
            .init(start: 2, end: 5, speaker: "A"),
            .init(start: 2.1, end: 2.117, speaker: "B"),
            .init(start: 2.4, end: 2.55, speaker: "B"),
            .init(start: 5.2, end: 6, speaker: "A"),
            .init(start: 6.1, end: 6.2, speaker: "B"),
            .init(start: 6.3, end: 7, speaker: "A"),
            .init(start: 9, end: 10, speaker: SpeakerInterval.unassigned)])
        XCTAssertEqual(turns.map(\.speaker), ["A", "B", "A", SpeakerInterval.unassigned])
        XCTAssertEqual(turns.map(\.start), [2, 6.1, 6.3, 9])
        XCTAssertEqual(turns.map(\.end), [6, 6.2, 7, 10])
        XCTAssertTrue(turns[0].overlapping)
        XCTAssertFalse(turns[1].overlapping)
    }

    func testArtificialWindowRemaindersKeepContextWithoutDroppingAFrame() {
        let duration = 25 + 1.0 / 16_000
        for plan in [MediaSegmentPlan.make(duration: duration, speakers: []),
                     MediaSegmentPlan.speechTurns(duration: duration, speakers: [
                        .init(start: 0, end: duration, speaker: "A"),
                        .init(start: 24.99, end: 25, speaker: "B")])] {
            XCTAssertEqual(plan.count, 2)
            XCTAssertEqual(plan.first?.startFrame, 0)
            XCTAssertEqual(plan.last?.endFrame, 400_001)
            XCTAssertEqual(plan[0].endFrame, plan[1].startFrame)
            XCTAssertTrue(plan.allSatisfy { (16_000...400_000).contains($0.endFrame - $0.startFrame) })
        }
    }

    func testSpeechTurnResumeSkipsGapsButKeepsShortAndUnassignedSpeech() async throws {
        let root = try directory(), history = try HistoryStore(directory: root)
        let asset = try history.saveRecording(samples: Array(repeating: 0.1, count: 40 * 16_000), source: .meeting)
        let document = try history.createDocument(asset: asset, title: "Gaps", configuration: .init(language: "en", localModel: .parakeet))
        let speech = SegmentSpeech(pauseAfterFirst: true)
        let first = MediaJobRunner(history: history, directory: root, factory: factory(speech), credentialReader: { _ in nil },
            speakerDecoder: { _, _ in [.init(start: 2, end: 32, speaker: "A"),
                .init(start: 35, end: 35.1, speaker: "B"),
                .init(start: 35.2, end: 36, speaker: SpeakerInterval.unassigned)] })
        first.resume(id: document.id)
        let deadline = Date().addingTimeInterval(5)
        while await speech.calls < 2 && Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        first.cancel(); try await wait(first)
        XCTAssertEqual(first.document?.completedSeconds, 27)
        let second = MediaJobRunner(history: history, directory: root, factory: factory(SegmentSpeech()), credentialReader: { _ in nil },
            speakerDecoder: { _, _ in XCTFail("Reuse persisted activity"); return [] })
        second.resume(id: document.id); try await wait(second)
        let final = try XCTUnwrap(second.document)
        XCTAssertEqual(final.stage, .completed)
        XCTAssertEqual(final.completedSeconds, 40)
        XCTAssertEqual(final.words.map(\.start), [2, 27, 35, 35.2])
        XCTAssertEqual(final.words.map(\.end), [27, 32, 35.1, 36])
        XCTAssertEqual(final.words.map(\.speaker), ["A", "A", "B", nil])
    }

    func testEmptySpeakerActivityOffersRecoveryInsteadOfFalseEmptySuccess() async throws {
        let root = try directory(), history = try HistoryStore(directory: root)
        let asset = try history.saveRecording(samples: Array(repeating: 0.1, count: 16_000), source: .meeting)
        let runner = MediaJobRunner(history: history, directory: root, factory: factory(SegmentSpeech()), credentialReader: { _ in nil },
            speakerDecoder: { _, _ in [] })
        runner.transcribeRecording(asset, configuration: .init(language: "en", localModel: .qwenSmall)); try await wait(runner)
        XCTAssertEqual(runner.document?.stage, .failed)
        XCTAssertTrue(runner.document?.issue?.contains("Without Speakers") == true)
        let id = try XCTUnwrap(runner.document?.id)
        runner.resume(id: id, withoutSpeakers: true); try await wait(runner)
        XCTAssertEqual(runner.document?.stage, .completed)
        XCTAssertFalse(runner.document?.words.isEmpty ?? true)
    }

    func testAppleMissingAssetsFailBeforeImplicitPreparation() async throws {
        let speech = SegmentSpeech(ready: false)
        do {
            _ = try await factory(speech).transcribeMediaWindow([0.1], offset: 0, config: .init(kind: .apple, appleLocale: "en-US"))
            XCTFail("Missing Apple assets must require explicit installation")
        } catch TranscriberError.modelNotDownloaded { }
        let prepared = await speech.prepares
        XCTAssertEqual(prepared, 0)
    }
    func testSilentMediaDoesNotInventTextButQuietSpeechStillRuns() async throws {
        let speech = SegmentSpeech(ready: false)
        let engine = factory(speech)
        let empty = try await engine.transcribeMediaWindow([0, -0.0], offset: 0, config: .init(kind: .qwen3))
        XCTAssertTrue(empty.isEmpty)
        let prepared = await speech.prepares
        XCTAssertEqual(prepared, 0)
        let quiet = try await engine.transcribeMediaWindow([0.00000001], offset: 0, config: .init(kind: .qwen3))
        XCTAssertEqual(quiet.count, 1)
    }

    func testEveryOlderRecordingAndAllVersionsSurviveReopenAndAudioRemoval() async throws {
        let root = try directory()
        let initial = try HistoryStore(directory: root)
        var assets: [RecordingAsset] = []
        for index in 0..<3 {
            assets.append(try initial.saveRecording(samples: Array(repeating: 0.1, count: 16_000), source: .meeting,
                createdAt: Date(timeIntervalSince1970: Double(100 + index))))
        }
        _ = try initial.saveRecording(samples: [0], source: .dictation)
        XCTAssertEqual(try initial.meetings().count, 3)
        XCTAssertEqual(try initial.recordings(source: .dictation).entries.count, 1)
        try initial.close()
        let reopened = try HistoryStore(directory: root)
        for asset in assets {
            let runner = MediaJobRunner(history: reopened, directory: root, factory: factory(SegmentSpeech()), credentialReader: { _ in nil },
                speakerDecoder: { _, _ in [.init(start: 0, end: 1, speaker: "1")] })
            runner.transcribeRecording(asset, configuration: .init(language: "en", localModel: .qwenSmall))
            try await wait(runner)
            XCTAssertEqual(runner.document?.recordingID, asset.id)
            XCTAssertEqual(runner.document?.stage, .completed)
            XCTAssertEqual(runner.document?.turns.first?.speaker, "1")
        }
        let extra = try reopened.createDocument(asset: assets[0], title: "Second version", configuration: .init())
        let entry = try XCTUnwrap(reopened.meetings().first { $0.asset?.id == assets[0].id })
        XCTAssertEqual(entry.documents.count, 2)
        XCTAssertTrue(entry.documents.contains { $0.id == extra.id })
        XCTAssertEqual(try reopened.meetings(query: "Second version").first?.documents.count, 2)
        let ids = try reopened.meetings(limit: 1).map(\.id) + reopened.meetings(limit: 2, offset: 1).map(\.id)
        XCTAssertEqual(Set(ids).count, 3)
        try reopened.deleteRecording(id: assets[0].id)
        let orphaned = try reopened.meetings().filter { $0.asset == nil }
        XCTAssertEqual(orphaned.count, 2)
        XCTAssertTrue(orphaned.allSatisfy { !$0.audioAvailable && $0.documents.count == 1 })
        try reopened.deleteHistoryKeepingAudio()
        XCTAssertEqual(try reopened.meetings().count, 2)
        XCTAssertTrue(try reopened.meetings().allSatisfy { $0.documents.isEmpty && $0.audioAvailable })
    }

    func testSegmentCheckpointResumesWithoutRediarizingOrLosingFinalFrame() async throws {
        let root = try directory(), history = try HistoryStore(directory: root)
        let frames = 61 * 16_000 + 1
        let asset = try history.saveRecording(samples: Array(repeating: 0.1, count: frames), source: .meeting)
        let document = try history.createDocument(asset: asset, title: "Resume", configuration: .init(language: "en", localModel: .parakeet))
        let speech = SegmentSpeech(pauseAfterFirst: true)
        let first = MediaJobRunner(history: history, directory: root, factory: factory(speech), credentialReader: { _ in nil },
            speakerDecoder: { _, duration in [.init(start: 0, end: duration, speaker: "A")] })
        first.resume(id: document.id)
        let deadline = Date().addingTimeInterval(5)
        while await speech.calls < 2 && Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        first.cancel(); try await wait(first)
        let checkpoint = try XCTUnwrap(history.document(id: document.id))
        XCTAssertEqual(checkpoint.completedSeconds, 25)
        XCTAssertEqual(checkpoint.words.count, 1)
        XCTAssertEqual(checkpoint.stage, .paused)
        XCTAssertTrue(checkpoint.diarizationComplete)
        XCTAssertNotNil(checkpoint.speakerIntervals)
        try history.close()
        let reopened = try HistoryStore(directory: root)
        let second = MediaJobRunner(history: reopened, directory: root, factory: factory(SegmentSpeech()), credentialReader: { _ in nil },
            speakerDecoder: { _, _ in XCTFail("Saved speaker identities must be reused"); return [] })
        second.resume(id: document.id); try await wait(second)
        let final = try XCTUnwrap(reopened.document(id: document.id))
        XCTAssertEqual(final.stage, .completed)
        XCTAssertEqual(final.words.count, 3)
        XCTAssertEqual(final.completedSeconds, Double(frames) / 16_000, accuracy: 1e-9)
        XCTAssertEqual(final.words.map(\.speaker), ["A", "A", "A"])
        XCTAssertTrue(final.words.allSatisfy { $0.timing == .segment })
        for pair in zip(final.words, final.words.dropFirst()) { XCTAssertEqual(pair.0.end, pair.1.start, accuracy: 1e-9) }
        let json = String(decoding: try TranscriptExport.data(final, format: .json), as: UTF8.self)
        XCTAssertTrue(json.contains("\"timing\" : \"segment\""))
        XCTAssertTrue(String(decoding: try TranscriptExport.data(final, format: .vtt), as: UTF8.self).hasPrefix("WEBVTT"))
    }

    func testDiarizationFirstFailureHasReachableRecoveryWithoutSpeakers() async throws {
        let root = try directory(), history = try HistoryStore(directory: root)
        let asset = try history.saveRecording(samples: Array(repeating: 0.1, count: 32_000), source: .meeting)
        let document = try history.createDocument(asset: asset, title: "Recovery", configuration: .init(language: "en", localModel: .cohere))
        let speech = SegmentSpeech()
        let runner = MediaJobRunner(history: history, directory: root, factory: factory(speech), credentialReader: { _ in nil },
            speakerDecoder: { _, _ in throw MediaError.insufficientMemory })
        runner.resume(id: document.id); try await wait(runner)
        XCTAssertEqual(runner.document?.stage, .failed)
        XCTAssertEqual(runner.document?.words.count, 0)
        runner.resume(id: document.id, withoutSpeakers: true); try await wait(runner)
        XCTAssertEqual(runner.document?.stage, .completed)
        XCTAssertEqual(runner.document?.configuration.selectedLocalModel, .cohere)
        XCTAssertFalse(runner.document?.configuration.identifySpeakers ?? true)
        XCTAssertNil(runner.document?.words.first?.speaker)
        XCTAssertFalse(runner.document?.words.isEmpty ?? true)
    }

    /// Read-only existing model files + recorded fixture; no playback, capture, downloads or provider calls.
    func testInstalledExpandedModelsAndSpeakerDetection() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let fixture = env["AIRDRAFT_MEETING_FIXTURE"], let modelNames = env["AIRDRAFT_MEETING_MODELS"] else {
            throw XCTSkip("Opt-in existing local models and recorded fixture")
        }
        let root = try directory(), history = try HistoryStore(directory: root)
        let asset = try history.importRecording(from: URL(fileURLWithPath: fixture))
        XCTAssertGreaterThan(asset.duration, 25)
        for name in modelNames.split(separator: ",") {
            let model = try XCTUnwrap(MediaConfiguration.LocalModel(rawValue: String(name)))
            let config = MediaConfiguration(language: model == .parakeet || model == .cohere ? "en" : "", localModel: model)
            XCTAssertTrue(LocalModels.isInstalled(config.asr), model.title)
            XCTAssertTrue(LocalSpeakerDiarizer.isInstalled)
            let engine = EngineFactory(status: EngineStatus(), credentialReader: { _ in nil })
            let runner = MediaJobRunner(history: history, directory: root, factory: engine, credentialReader: { _ in nil })
            runner.transcribeRecording(asset, configuration: config)
            try await wait(runner, seconds: 240)
            let result = try XCTUnwrap(runner.document)
            if let output = env["AIRDRAFT_MEETING_EVIDENCE"] {
                let directory = URL(fileURLWithPath: output, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(result).write(to: directory.appendingPathComponent(model.rawValue + ".json"))
            }
            XCTAssertEqual(result.stage, .completed, result.issue ?? model.title)
            XCTAssertFalse(result.words.isEmpty)
            XCTAssertTrue(result.words.contains { $0.speaker != nil })
            XCTAssertTrue(result.words.contains { $0.start >= 25 && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, "Speech after 25 seconds was lost")
            if let minimum = env["AIRDRAFT_MEETING_MIN_SPEAKERS"].flatMap(Int.init) {
                XCTAssertGreaterThanOrEqual(Set(result.words.compactMap(\.speaker)).count, minimum)
                for phrase in ["diane", "chicago", "new jersey"] {
                    XCTAssertTrue(result.text.lowercased().contains(phrase), "Missing fixture phrase: \(phrase) (\(model.title))")
                }
                XCTAssertFalse(result.text.lowercased().contains("the most common form"))
                XCTAssertNil(result.text.range(of: #"(.)\1{10,}"#, options: .regularExpression))
                XCTAssertTrue(result.words.allSatisfy { $0.end - $0.start >= 0.25 }, "Overlaps fragmented speech context")
            }
            XCTAssertEqual(result.recordingID, asset.id)
            XCTAssertTrue(result.words.allSatisfy { $0.end <= asset.duration + 0.001 && $0.start >= 0 })
            print("MEETING_NATIVE model=\(model.rawValue) duration=\(asset.duration) speakers=\(Set(result.words.compactMap(\.speaker)).count) segments=\(result.words.count) text=\(result.text)")
            await engine.unloadAll()
        }
    }
}

private actor SegmentSpeech: Transcriber {
    nonisolated let id = "fixture:local-segment"
    private var ready: Bool
    let pauseAfterFirst: Bool
    private(set) var calls = 0
    private(set) var prepares = 0
    init(ready: Bool = true, pauseAfterFirst: Bool = false) { self.ready = ready; self.pauseAfterFirst = pauseAfterFirst }
    func isReady() -> Bool { ready }
    func prepare() { prepares += 1; ready = true }
    func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        calls += 1
        if pauseAfterFirst && calls > 1 { try await Task.sleep(for: .seconds(30)) }
        return Transcript(text: "segment\(calls)", engine: id, latencyMs: 0)
    }
    func unload() { ready = false }
}
