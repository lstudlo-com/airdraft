import XCTest
import AVFoundation
@testable import AirdraftCore

final class MediaDocumentTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Airdraft-MediaTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func fixture(_ history: HistoryStore, duration: Double = 1) throws -> RecordingAsset {
        try history.saveRecording(samples: Array(repeating: 0, count: Int(duration * 16_000)), source: .imported)
    }
    /// Opt-in direct-file integration. No speaker output, microphone, Keychain or daily data access.
    func testInstalledLocalInferenceOnRecordedFixture() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["AIRDRAFT_MEDIA_INFERENCE"] == "1",
              let fixturePath = environment["AIRDRAFT_MEDIA_FIXTURE"] else { throw XCTSkip("Opt-in recorded-file model integration") }
        let root = try directory()
        let previous = environment["AIRDRAFT_E2E_MODEL_ROOT"]
        setenv("AIRDRAFT_E2E_MODEL_ROOT", root.appendingPathComponent("Models").path, 1)
        defer {
            if let previous { setenv("AIRDRAFT_E2E_MODEL_ROOT", previous, 1) }
            else { unsetenv("AIRDRAFT_E2E_MODEL_ROOT") }
        }
        let configuration = ASRConfig(kind: .whisperKit, whisperModel: "large-v3-v20240930_turbo", language: "en")
        try await ModelDownloader.shared.download(configuration) { _ in }
        try await ModelDownloader.shared.downloadSpeakerModel { _ in }
        let normalized = root.appendingPathComponent("fixture.wav")
        let duration = try await MediaAudioDecoder.normalize(URL(fileURLWithPath: fixturePath), to: normalized)
        let factory = await EngineFactory(status: EngineStatus(), credentialReader: { _ in nil })
        let samples = try MediaAudioWindow.read(normalized, from: 0)
        let rms = sqrt(samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(samples.count))
        print("MEDIA_FIXTURE_PCM rms=\(rms) frames=\(samples.count)")
        XCTAssertGreaterThan(rms, 0.05)
        let words = try await factory.transcribeMediaWindow(samples, offset: 0, config: configuration)
        XCTAssertFalse(words.isEmpty)
        XCTAssertTrue(words.map(\.text).joined().lowercased().contains("country"))
        await factory.unloadAll()
        let speakers = try await LocalSpeakerDiarizer.identify(url: normalized, duration: duration) { _ in }
        XCTAssertFalse(speakers.isEmpty)
        let aligned = SpeakerReconciliation.align(words, speakers: speakers)
        XCTAssertTrue(aligned.contains { $0.speaker != nil })
        print("MEDIA_RECORDED_FIXTURE duration=\(duration) words=\(words.count) speakers=\(Set(speakers.map(\.speaker)).count) text=\(words.map(\.text).joined())")
    }

    func testCleanupScopesRetainIndependentAudioAndPreventDocumentResurrection() throws {
        let history = try HistoryStore(directory: directory())
        let asset = try fixture(history)
        let original = try history.createDocument(asset: asset, title: "Interview", configuration: .init())
        var edited = original
        edited.words = [.init(start: 0, end: 1, text: "private text", speaker: "1")]; edited.rebuildTurns()
        edited.speakerNames = ["1": "Private name"]; edited.summary = "private summary"
        edited = try history.updateDocument(edited)
        XCTAssertThrowsError(try history.updateDocument(original))
        XCTAssertEqual(try history.historyItems().count, 1)
        XCTAssertEqual(try history.stats().dictations, 0)
        XCTAssertEqual(try history.recordings(query: "private").entries.count, 1)
        try history.deleteHistoryKeepingAudio()
        XCTAssertNil(try history.document(id: edited.id))
        XCTAssertNotNil(history.audioURL(for: asset))
        XCTAssertThrowsError(try history.updateDocument(edited))
        XCTAssertEqual(try history.recordings(query: "private").entries.count, 0)
        let replacement = try history.createDocument(asset: asset, title: "Survives", configuration: .init())
        try history.deleteAllAudio()
        XCTAssertNil(try history.document(id: replacement.id)?.recordingID)
        XCTAssertEqual(try history.document(id: replacement.id)?.title, "Survives")
        try history.deleteAll()
        XCTAssertEqual(try history.documents().count, 0)
    }
    func testAlignmentLeavesGapsUnknownAndMarksOverlapAcrossGlobalSpeakers() {
        let words: [TranscriptWord] = [.init(start: 0, end: 1, text: "A"), .init(start: 2, end: 3, text: " B"), .init(start: 5, end: 6, text: " C")]
        let result = SpeakerReconciliation.align(words, speakers: [.init(start: 0, end: 1, speaker: "1"), .init(start: 2, end: 3, speaker: "2"), .init(start: 2.2, end: 3, speaker: "1")])
        XCTAssertEqual(result[0].speaker, "1"); XCTAssertEqual(result[1].speaker, "2")
        XCTAssertTrue(result[1].overlapping); XCTAssertNil(result[2].speaker)
        XCTAssertEqual(TranscriptTurn.group(result).count, 3)
    }
    func testExportsPreserveOriginalAndEscapeWebVTT() throws {
        var document = TranscriptDocument(recordingID: "asset", title: "Test", configuration: .init())
        document.words = [.init(start: 3661.001, end: 3662.5, text: "Original", speaker: "1")]; document.rebuildTurns()
        document.turns[0].editedText = "Edited <text>"; document.speakerNames["1"] = "A&B"
        let srt = String(decoding: try TranscriptExport.data(document, format: .srt), as: UTF8.self)
        XCTAssertTrue(srt.contains("01:01:01,001 --> 01:01:02,500"))
        let vtt = String(decoding: try TranscriptExport.data(document, format: .vtt), as: UTF8.self)
        XCTAssertTrue(vtt.hasPrefix("WEBVTT\n")); XCTAssertTrue(vtt.contains("A&amp;B: Edited &lt;text&gt;"))
        let json = String(decoding: try TranscriptExport.data(document, format: .json), as: UTF8.self)
        XCTAssertTrue(json.contains("Original")); XCTAssertTrue(json.contains("Edited")); XCTAssertFalse(json.contains("remoteFileID"))
        document.turns[0].speaker = "2"
        document.speakerNames["2"] = "Reassigned"
        document.summary = "Separate summary"
        let original = String(decoding: try TranscriptExport.data(document, format: .txt, original: true), as: UTF8.self)
        XCTAssertTrue(original.contains("A&B: Original")); XCTAssertFalse(original.contains("Edited"))
        XCTAssertFalse(original.contains("Reassigned")); XCTAssertFalse(original.contains("Separate summary"))
    }
    func testNormalizedFileUsesBoundedWindowsAndRejectsInvalidMedia() async throws {
        let root = try directory()
        let source = root.appendingPathComponent("source.wav")
        try WAVEncoder.encode(samples: Array(repeating: 0.25, count: 40 * 16_000)).write(to: source)
        let target = root.appendingPathComponent("normalized.wav")
        let duration = try await MediaAudioDecoder.normalize(source, to: target)
        XCTAssertEqual(duration, 40, accuracy: 0.01)
        XCTAssertEqual(try MediaAudioWindow.read(target, from: 25).count, 15 * 16_000)
        XCTAssertEqual(try MediaAudioWindow.read(target, from: 40).count, 0)
    }
    @MainActor func testThirtySixtyAndHundredTwentyMinuteFilesRemainWindowBounded() async throws {
        for minutes in [30, 60, 120] {
            let root = try directory()
            let wav = root.appendingPathComponent("long.wav")
            // Write silence directly to disk. This test never instantiates an output device.
            let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
            do {
                let file = try AVAudioFile(forWriting: wav, settings: [AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false], commonFormat: .pcmFormatFloat32, interleaved: false)
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
                buffer.frameLength = 16_000
                buffer.floatChannelData![0].initialize(repeating: 0, count: 16_000)
                for _ in 0..<(minutes * 60) { try file.write(from: buffer) }
            }
            let history = try HistoryStore(directory: root)
            let asset = try history.importRecording(from: wav)
            let document = try history.createDocument(asset: asset, title: "Long silent fixture", configuration: .init(identifySpeakers: false))
            let runner = MediaJobRunner(history: history, directory: root, factory: EngineFactory(status: EngineStatus(), credentialReader: { _ in nil }),
                credentialReader: { _ in nil }, windowDecoder: { samples, offset, _ in
                    XCTAssertLessThanOrEqual(samples.count, 25 * 16_000)
                    return [.init(start: offset, end: offset + Double(samples.count) / 16_000, text: " window")]
                })
            runner.resume(id: document.id)
            let deadline = Date().addingTimeInterval(60)
            while runner.isBusy && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertFalse(runner.isBusy)
            let result = try XCTUnwrap(history.document(id: document.id))
            XCTAssertEqual(result.stage, .completed)
            XCTAssertEqual(result.completedSeconds, Double(minutes * 60), accuracy: 0.001)
            XCTAssertEqual(result.words.last?.end ?? 0, Double(minutes * 60), accuracy: 0.001)
            for pair in zip(result.words, result.words.dropFirst()) { XCTAssertEqual(pair.0.end, pair.1.start, accuracy: 0.001) }
            try history.close()
        }
    }

    @MainActor func testDiarizationFailureKeepsTextAndResumeSkipsASR() async throws {
        let root = try directory(); let history = try HistoryStore(directory: root)
        let asset = try fixture(history, duration: 28)
        let document = try history.createDocument(asset: asset, title: "Silent fixture", configuration: .init())
        let calls = Counter()
        let first = MediaJobRunner(history: history, directory: root, factory: EngineFactory(status: EngineStatus(), credentialReader: { _ in nil }),
            credentialReader: { _ in nil }, windowDecoder: { samples, offset, _ in
                await calls.increment()
                return [.init(start: offset, end: offset + Double(samples.count) / 16_000, text: " word")]
            }, speakerDecoder: { _, _ in throw MediaError.missingSpeakerModel })
        first.resume(id: document.id)
        while first.isBusy { try await Task.sleep(for: .milliseconds(10)) }
        let saved = try XCTUnwrap(history.document(id: document.id))
        XCTAssertTrue(saved.transcriptionComplete); XCTAssertFalse(saved.words.isEmpty); XCTAssertEqual(saved.stage, .failed)
        let before = await calls.value
        let second = MediaJobRunner(history: history, directory: root, factory: EngineFactory(status: EngineStatus(), credentialReader: { _ in nil }),
            credentialReader: { _ in nil }, windowDecoder: { _, _, _ in await calls.increment(); return [] },
            speakerDecoder: { _, _ in [.init(start: 0, end: 28, speaker: "1")] })
        second.resume(id: document.id)
        while second.isBusy { try await Task.sleep(for: .milliseconds(10)) }
        let after = await calls.value
        XCTAssertEqual(before, after)
        XCTAssertEqual(try history.document(id: document.id)?.stage, .completed)
        XCTAssertEqual(try history.document(id: document.id)?.turns.first?.speaker, "1")
    }
    @MainActor func testCancelledLateWindowDoesNotCheckpointAndCanResumeAfterRelaunch() async throws {
        let root = try directory(); let history = try HistoryStore(directory: root)
        let asset = try fixture(history, duration: 30)
        let document = try history.createDocument(asset: asset, title: "Cancel", configuration: .init(identifySpeakers: false))
        let started = Counter()
        let runner = MediaJobRunner(history: history, directory: root, factory: EngineFactory(status: EngineStatus(), credentialReader: { _ in nil }),
            credentialReader: { _ in nil }, windowDecoder: { _, _, _ in
                await started.increment()
                try? await Task.sleep(for: .milliseconds(100))
                return [.init(start: 0, end: 1, text: "Late")]
            })
        runner.resume(id: document.id)
        while await started.value == 0 { try await Task.sleep(for: .milliseconds(5)) }
        runner.cancel()
        while runner.isBusy { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(try history.document(id: document.id)?.stage, .paused)
        XCTAssertEqual(try history.document(id: document.id)?.words.count, 0)
        XCTAssertEqual(try history.document(id: document.id)?.completedSeconds, 0)
    }
}
private actor Counter {
    var value = 0
    func increment() { value += 1 }
}
