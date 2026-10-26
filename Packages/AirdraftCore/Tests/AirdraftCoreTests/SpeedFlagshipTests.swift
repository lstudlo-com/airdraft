import AppKit
import Foundation
import XCTest
@testable import AirdraftCore

/// AD-104: flags, send decisions, profile destinations, the Edit shortcut and
/// local measurements. Every OS boundary is injected; nothing is pasted, no key
/// is posted and no real History or preferences are read.
final class HighRiskFlagsTests: XCTestCase {
    /// Ordinary cleanup stays unflagged; changed numbers, flipped negations, introduced
    /// names and speech-guard corrections are flagged by kind.
    func testOrdinaryCleanupIsQuietAndRiskyChangesAreFlaggedByKind() {
        let flags = HighRiskFlags.flags(raw: "um so i think we should ship it tomorrow you know",
                                        final: "So I think we should ship it tomorrow.")
        XCTAssertEqual(flags, [])

        // Numbers, both ways.
        let added = HighRiskFlags.flags(raw: "set the timeout to fifteen seconds", final: "Set the timeout to 50 seconds.")
        XCTAssertEqual(added.map(\.kind), [.number])
        XCTAssertEqual(added.first?.text, "50")
        let removed = HighRiskFlags.flags(raw: "use port 8080 please", final: "Use the default port, please.")
        XCTAssertEqual(removed.map(\.text), ["8080"])
        XCTAssertEqual(HighRiskFlags.flags(raw: "port ８０８０", final: "Port 8080."), [], "Full-width digits read as ASCII")

        // Negation in English and Chinese.
        let english = HighRiskFlags.flags(raw: "do not restart the server", final: "Restart the server.")
        XCTAssertEqual(english.map(\.kind), [.negation])
        XCTAssertEqual(english.first?.text, "not")
        let chinese = HighRiskFlags.flags(raw: "今天先不要部署", final: "今天先部署。")
        XCTAssertEqual(chinese.map(\.kind), [.negation])
        XCTAssertEqual(HighRiskFlags.flags(raw: "我沒有空", final: "我没有空。"), [],
                       "Script conversion keeps the same count of negations")

        // Names refinement introduced, unless Vocabulary trusts them.
        let names = HighRiskFlags.flags(raw: "deploy it with kuber netes", final: "Deploy it with Kubernetes.")
        XCTAssertEqual(names.map(\.kind), [.newTerm])
        XCTAssertEqual(names.first?.text, "Kubernetes")
        XCTAssertEqual(HighRiskFlags.flags(raw: "deploy it with kuber netes", final: "Deploy it with Kubernetes.",
                                           vocabulary: ["Kubernetes"]), [])
        XCTAssertEqual(HighRiskFlags.flags(raw: "ask claude to review", final: "Ask Claude to review."), [],
                       "A name the speech already contained only changed case")

        // Speech-guard corrections.
        let recognition = HighRiskFlags.flags(raw: "hello there", final: "Hello there.", adjustments: [.repetitionTrimmed])
        XCTAssertEqual(recognition.map(\.kind), [.recognition])
        XCTAssertEqual(HighRiskFlags.flags(raw: "hello there", final: "Hello there.", adjustments: [.punctuationAdded]), [])
    }

    /// Identifiers flag and can stop holding the send; snippets carry context and are bounded.
    func testIdentifiersFlagAndCanStopHoldingTheSendWithBoundedSnippets() {
        let flags = HighRiskFlags.flags(raw: "open user_settings.json and fix fetchUser", final: "Open user_settings.json and fix fetchUser.")
        XCTAssertEqual(Set(flags.map(\.text)), ["user_settings.json", "fetchUser"])
        XCTAssertTrue(flags.allSatisfy { $0.kind == .identifier && $0.holdsSend })
        let relaxed = HighRiskFlags.flags(raw: "open user_settings.json", final: "Open user_settings.json.", identifiersHoldSend: false)
        XCTAssertEqual(relaxed.count, 1)
        XCTAssertEqual(HighRiskFlags.holdingSend(relaxed), [])

        XCTAssertEqual(HighRiskFlags.snippet(for: "8080", in: "Please use port 8080 on the staging host"), "…se port 8080 on the…")
        let many = (0..<40).map { "v\($0)x" }.joined(separator: " ")
        XCTAssertEqual(HighRiskFlags.flags(raw: many, final: many).count, HighRiskFlags.maximumStored)
    }
}

@MainActor
final class SendDecisionTests: XCTestCase {
    private let flag = DictationFlag(kind: .number, text: "50", snippet: "to 50 seconds")

    /// Automatic send only for AI chats and agents; Shift waits longer and respects confirmation.
    func testAutomaticSendIsOnlyForAIChatsAndShiftSendRespectsConfirmation() {
        let options = SpeedOptions()
        XCTAssertEqual(DictationPipeline.sendDecision(request: .auto, delivered: .delivered, bundleID: "com.openai.chat",
                                                      flags: [], options: options), .send(window: DictationPipeline.aiSendWindow))
        for person in ["com.apple.mail", "com.tinyspeck.slackmacgap", "com.apple.MobileSMS", "com.apple.Safari", "com.google.Chrome"] {
            XCTAssertEqual(DictationPipeline.sendDecision(request: .auto, delivered: .delivered, bundleID: person,
                                                          flags: [], options: options), .none, person)
        }
        XCTAssertEqual(DictationPipeline.sendDecision(request: .auto, delivered: .delivered,
                                                      bundleID: "com.google.Chrome.app.abcdef", flags: [], options: options),
                       .send(window: DictationPipeline.aiSendWindow), "An installed web app has its own bundle ID")
        XCTAssertEqual(DictationPipeline.sendDecision(request: .auto, delivered: .sentUnverified, bundleID: "dev.warp.Warp-Stable",
                                                      flags: [], options: options), .none, "Never automatic without confirmation")

        var shiftOptions = SpeedOptions()
        XCTAssertEqual(DictationPipeline.sendDecision(request: .shift, delivered: .delivered, bundleID: "com.tinyspeck.slackmacgap",
                                                      flags: [], options: shiftOptions), .send(window: DictationPipeline.personSendWindow))
        guard case .blocked = DictationPipeline.sendDecision(request: .shift, delivered: .sentUnverified, bundleID: "dev.zed.Zed",
                                                             flags: [], options: shiftOptions) else { return XCTFail("Unconfirmed paste must not send") }
        shiftOptions.sendsWhenUnconfirmed = true
        XCTAssertEqual(DictationPipeline.sendDecision(request: .shift, delivered: .sentUnverified, bundleID: "dev.zed.Zed",
                                                      flags: [], options: shiftOptions), .send(window: DictationPipeline.personSendWindow))
        guard case .blocked = DictationPipeline.sendDecision(request: .shift, delivered: .delivered, bundleID: "com.apple.mail",
                                                             flags: [], options: shiftOptions) else { return XCTFail("Mail does not send with Return") }
        XCTAssertEqual(DictationPipeline.sendDecision(request: .shift, delivered: .notDelivered, bundleID: "com.openai.chat",
                                                      flags: [], options: shiftOptions), .none)
        XCTAssertEqual(DictationPipeline.sendDecision(request: nil, delivered: .delivered, bundleID: "com.openai.chat",
                                                      flags: [flag], options: shiftOptions), .none)
    }

    /// Holding flags keep the text pasted without sending; the held notice lists at most three.
    func testHoldingFlagsKeepTheTextUnsentAndTheNoticeListsAtMostThree() {
        XCTAssertEqual(DictationPipeline.sendDecision(request: .auto, delivered: .delivered, bundleID: "com.openai.chat",
                                                      flags: [flag], options: SpeedOptions()), .hold([flag]))
        let quiet = DictationFlag(kind: .identifier, text: "fetchUser", snippet: "fix fetchUser", holdsSend: false)
        XCTAssertEqual(DictationPipeline.sendDecision(request: .auto, delivered: .delivered, bundleID: "com.openai.chat",
                                                      flags: [quiet], options: SpeedOptions()), .send(window: DictationPipeline.aiSendWindow))

        let flags = (1...5).map { DictationFlag(kind: .number, text: "\($0)", snippet: "n\($0)") }
        let notice = DictationPipeline.heldNotice(flags, handling: .showAndWait)
        XCTAssertTrue(notice.contains("“n1”") && notice.contains("“n3”"))
        XCTAssertFalse(notice.contains("“n4”"))
        XCTAssertFalse(DictationPipeline.heldNotice(flags, handling: .pasteOnly).contains("“n1”"))
    }
}

final class ProfileOutputTests: XCTestCase {
    /// Older profile files decode without output or send; cursor delivery follows the app
    /// default only without the profile's own choice; Shift shortcuts cannot lock a send.
    func testProfileOutputDecodingCursorDeliveryAndShiftShortcuts() throws {
        let json = #"{"id":"6B1F0C1E-0000-4000-8000-000000000001","name":"Clean","symbol":"sparkles","usesLLM":true,"task":"","instructions":"x","isBuiltIn":true}"#
        let profile = try JSONDecoder().decode(RefinementProfile.self, from: Data(json.utf8))
        XCTAssertNil(profile.output)
        XCTAssertFalse(profile.sendsAutomatically)
        var updated = profile
        updated.output = ProfileOutput(kind: .file, filePath: "~/Notes/{date}.md")
        updated.sendsAutomatically = true
        let roundTrip = try JSONDecoder().decode(RefinementProfile.self, from: JSONEncoder().encode(updated))
        XCTAssertEqual(roundTrip, updated)

        var cursor = RefinementProfile(name: "AI", instructions: "")
        XCTAssertTrue(cursor.deliversToCursor(appDefault: .cursor))
        XCTAssertFalse(cursor.deliversToCursor(appDefault: .script))
        cursor.output = .copy
        XCTAssertFalse(cursor.deliversToCursor(appDefault: .cursor))
        cursor.output = .cursor
        XCTAssertTrue(cursor.deliversToCursor(appDefault: .script))

        XCTAssertTrue(Hotkey(keyCode: 49, modifiers: Hotkey.maskShift | Hotkey.maskCommand).usesShift)
        XCTAssertTrue(Hotkey(keyCode: 60, isModifierOnly: true).usesShift)
        XCTAssertFalse(Hotkey.controlOption.usesShift)
    }

    /// Duplicates keep output and send; practice never sends or writes elsewhere; speed
    /// settings persist and profile shortcuts are bounded.
    @MainActor
    func testDuplicationPracticeAndSpeedSettingsPersistence() throws {
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("speed-profiles-\(UUID())")
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = ProfileStore(directory: directory)
            var clean = store.activeProfile
            clean.output = .copy
            clean.sendsAutomatically = true
            store.update(clean)
            let copy = try XCTUnwrap(store.duplicate(id: clean.id))
            XCTAssertEqual(copy.output, .copy)
            XCTAssertTrue(copy.sendsAutomatically)
        }

        do {
            let suite = "speed-practice-\(UUID())"
            defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
            let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
            var profile = RefinementProfile(name: "AI", instructions: "")
            profile.output = .copy
            profile.sendsAutomatically = true
            settings.beginOnboardingPractice()
            let practice = settings.effectiveProfile(profile)
            XCTAssertNil(practice.output)
            XCTAssertFalse(practice.sendsAutomatically)
            settings.endOnboardingPractice()
        }

        let suite = "speed-settings-\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertFalse(settings.sendWithShift)
        XCTAssertEqual(settings.flagHandling, .showAndWait)
        XCTAssertTrue(settings.identifiersHoldSend)
        XCTAssertNil(settings.editHotkey)
        XCTAssertFalse(settings.hadExistingSetup)
        settings.sendWithShift = true
        settings.flagHandling = .pasteOnly
        settings.editHotkey = Hotkey(keyCode: 14, modifiers: Hotkey.maskControl | Hotkey.maskAlternate)
        settings.profileHotkeys = (0..<4).map { _ in ProfileHotkey(profileID: RefinementProfile.cleanID) }
        XCTAssertEqual(settings.profileHotkeys.count, ProfileHotkey.maximumCount)
        let reloaded = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertTrue(reloaded.sendWithShift)
        XCTAssertEqual(reloaded.flagHandling, .pasteOnly)
        XCTAssertEqual(reloaded.editHotkey, settings.editHotkey)
        XCTAssertEqual(reloaded.profileHotkeys.count, ProfileHotkey.maximumCount)
        reloaded.editHotkey = nil
        XCTAssertNil(AppSettings(defaults: UserDefaults(suiteName: suite)!).editHotkey)
    }
}

final class FileAppendDeliveryTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("speed-append-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Template fields fill without letting app names escape the folder, unusable
    /// templates report a reason, and each dictation becomes its own line.
    func testTemplatesUnavailableReasonsAndOneLinePerDictation() async throws {
        let date = Date(timeIntervalSince1970: 1_793_000_000)
        let path = FileAppendDelivery.resolvedPath("/tmp/{date} {time} {app}.md", app: "Evil/../App", date: date)
        XCTAssertFalse(path.contains("{"))
        XCTAssertTrue(path.hasPrefix("/tmp/"))
        XCTAssertFalse(path.dropFirst(5).contains("/"), "An app name cannot add a folder")
        XCTAssertTrue(FileAppendDelivery.resolvedPath("~/x.md", app: nil).hasPrefix("/"))

        XCTAssertNotNil(FileAppendDelivery.unavailableReason(template: ""))
        XCTAssertNotNil(FileAppendDelivery.unavailableReason(template: "relative/path.md"))
        XCTAssertNotNil(FileAppendDelivery.unavailableReason(template: directory.path), "A folder is not a file")
        XCTAssertNotNil(FileAppendDelivery.unavailableReason(template: directory.appendingPathComponent("missing/x.md").path))
        XCTAssertNil(FileAppendDelivery.unavailableReason(template: directory.appendingPathComponent("new.md").path))

        let file = directory.appendingPathComponent("notes.md")
        try Data("Existing line without newline".utf8).write(to: file)
        try await FileAppendDelivery.append("First", template: file.path, app: nil)
        try await FileAppendDelivery.append("Second", template: file.path, app: nil)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "Existing line without newline\nFirst\nSecond\n")
        let fresh = directory.appendingPathComponent("{app}.md")
        try await FileAppendDelivery.append("Only", template: fresh.path, app: "Journal")
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("Journal.md"), encoding: .utf8), "Only\n")
    }
}

final class SpeedMetricsStoreTests: XCTestCase {
    /// Speed counts persist and stay bounded; History stores flags and the send outcome.
    func testSpeedCountsPersistAndHistoryStoresFlagsAndSendOutcome() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("speed-metrics-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SpeedMetricsStore(directory: directory)
        await store.noteAcceptedPress()
        await store.noteAcceptedPress()
        await store.noteIgnoredPress()
        for ms in [100, 300, 200] { await store.noteCapture(ms: ms, transport: "builtIn") }
        await store.noteDelivery(bundleID: "com.openai.chat", status: .delivered)
        await store.noteDelivery(bundleID: "com.openai.chat", status: .notDelivered)
        await store.noteDelivery(bundleID: "dev.warp.Warp-Stable", status: .sentUnverified)
        await store.noteDelivery(bundleID: nil, status: .delivered)

        let reloaded = await SpeedMetricsStore(directory: directory).snapshot()
        XCTAssertEqual(reloaded.acceptedPresses, 2)
        XCTAssertEqual(reloaded.ignoredPerHundred, 50)
        XCTAssertEqual(reloaded.medianCaptureMs(transport: "builtIn"), 200)
        XCTAssertEqual(reloaded.deliveries["com.openai.chat"], .init(delivered: 1, sentUnverified: 0, notDelivered: 1))
        let ai = reloaded.deliveries(matching: SpeedMetricsSnapshot.aiDestinationPrefixes)
        XCTAssertEqual(ai.total, 3)
        let json = try String(contentsOf: directory.appendingPathComponent(SpeedMetricsStore.filename), encoding: .utf8)
        XCTAssertFalse(json.contains("text"), "Counts only")

        for _ in 0..<(SpeedMetricsSnapshot.maximumSamples + 5) { await store.noteCapture(ms: 1, transport: "usb") }
        let bounded = await store.snapshot()
        XCTAssertEqual(bounded.captureSamples.count, SpeedMetricsSnapshot.maximumSamples)
        XCTAssertEqual(SpeedMetricsStore.transportName(nil), "unknown")

        let history = try HistoryStore(inMemory: true)
        let flag = DictationFlag(kind: .number, text: "50", snippet: "to 50 s")
        try history.save(DictationRecord(mode: "Clean", family: "general", rawTranscript: "a", refinedText: "a", finalText: "a",
                                         asrEngine: "t", audioSeconds: 1, asrMs: 1, llmMs: 0, inserted: true,
                                         outputDestination: "cursor", outputSucceeded: true,
                                         flags: DictationRecord.encodeFlags([flag]), sendRequest: SendRequest.auto.rawValue, submitted: false))
        try history.save(DictationRecord(mode: "Clean", family: "general", rawTranscript: "b", refinedText: "b", finalText: "b",
                                         asrEngine: "t", audioSeconds: 1, asrMs: 1, llmMs: 0, inserted: false,
                                         outputDestination: DictationRecord.copyDestination, outputSucceeded: true,
                                         flags: "[]", sendRequest: SendRequest.shift.rawValue, submitted: true))
        try history.save(DictationRecord(mode: "Clean", family: "general", rawTranscript: "c", refinedText: "c", finalText: "c",
                                         asrEngine: "t", audioSeconds: 1, asrMs: 1, llmMs: 0, inserted: true))
        let records = try history.recent()
        let flagged = try XCTUnwrap(records.first { $0.rawTranscript == "a" })
        XCTAssertEqual(flagged.decodedFlags, [flag])
        XCTAssertEqual(flagged.submitted, false)
        XCTAssertEqual(try XCTUnwrap(records.first { $0.rawTranscript == "b" }).deliveryStatus, .delivered,
                       "A copy-only profile's intended outcome is delivered")
        let stats = try history.speedStatistics()
        XCTAssertEqual(stats.checked, 2)
        XCTAssertEqual(stats.flagged, 1)
        XCTAssertEqual(stats.holding, 1)
        XCTAssertEqual(stats.sendRequested, 2)
        XCTAssertEqual(stats.sent, 1)
    }
}

/// Each phase builds its own `SpeedFixture`, so phases share no pipeline, history or settings.
@MainActor
final class SpeedPipelineTests: XCTestCase {
    /// Automatic send presses Return once after a confirmed paste; flagged words hold it
    /// and say why; Esc during the window keeps the paste and sends nothing.
    func testAutomaticSendPressesReturnOnceUnlessFlagsOrEscHoldIt() async throws {
        do {
            let fixture = try SpeedFixture(speech: "Summarize the meeting notes")
            defer { fixture.cleanUp() }
            fixture.setActiveProfile(output: nil, sendsAutomatically: true)
            try await fixture.dictate()
            XCTAssertEqual(fixture.probe.insertedTexts, ["Summarize the meeting notes"])
            XCTAssertEqual(fixture.probe.returns, 1)
            let record = try XCTUnwrap(fixture.history.recent().first)
            XCTAssertEqual(record.sendRequest, SendRequest.auto.rawValue)
            XCTAssertEqual(record.submitted, true)
            XCTAssertEqual(record.flags, "[]")
            XCTAssertNotNil(fixture.pipeline.lastOutcome?.timings.stopToSubmitMs)
        }

        do {
            let fixture = try SpeedFixture(speech: "Restart user_service on port 8080")
            defer { fixture.cleanUp() }
            fixture.setActiveProfile(output: nil, sendsAutomatically: true)
            var states: [PipelineState] = []
            fixture.pipeline.onStateChange = { states.append($0) }
            try await fixture.dictate()
            XCTAssertEqual(fixture.probe.insertedTexts.count, 1, "The text is still pasted")
            XCTAssertEqual(fixture.probe.returns, 0)
            XCTAssertTrue(states.contains { if case .notice(let text, _) = $0 { return text.contains("user_service") }; return false })
            XCTAssertEqual(try fixture.history.recent().first?.submitted, false)
            XCTAssertFalse(fixture.pipeline.holdsRecordingWindow)
        }

        let fixture = try SpeedFixture(speech: "Message for the team")
        defer { fixture.cleanUp() }
        fixture.setActiveProfile(output: nil, sendsAutomatically: true)
        fixture.pipeline.startRecording()
        try await waitUntil("recording") { fixture.pipeline.isRecording }
        fixture.pipeline.stopAndProcess()
        try await waitUntil("send pending") { fixture.pipeline.isSendPending }
        fixture.pipeline.cancelPendingSend()
        try await fixture.finished()
        XCTAssertEqual(fixture.probe.insertedTexts.count, 1, "Esc keeps the paste")
        XCTAssertEqual(fixture.probe.returns, 0, "Esc sends nothing")
        XCTAssertEqual(try fixture.history.recent().first?.submitted, false)
    }

    /// Shift during recording locks a send, but not while the feature is off or Shift
    /// is part of the shortcut.
    func testShiftLocksASendOnlyWhenEnabledAndNotPartOfTheShortcut() async throws {
        do {
            let fixture = try SpeedFixture(speech: "Thanks, see you tomorrow")
            defer { fixture.cleanUp() }
            fixture.settings.sendWithShift = true
            fixture.pipeline.startRecording()
            try await waitUntil("recording") { fixture.pipeline.isRecording }
            fixture.keyboard.value = Hotkey.maskShift
            try await waitUntil("Shift locks the send") { fixture.pipeline.sendLocked }
            fixture.keyboard.value = 0
            try await Task.sleep(for: .milliseconds(80))
            fixture.pipeline.stopAndProcess()
            try await fixture.finished()
            XCTAssertEqual(fixture.probe.returns, 1)
            XCTAssertEqual(try fixture.history.recent().first?.sendRequest, SendRequest.shift.rawValue)
        }

        let fixture = try SpeedFixture(speech: "Plain words")
        defer { fixture.cleanUp() }
        fixture.keyboard.value = 0
        fixture.pipeline.startRecording()
        try await waitUntil("recording") { fixture.pipeline.isRecording }
        fixture.keyboard.value = Hotkey.maskShift
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(fixture.pipeline.sendLocked, "Feature off")
        fixture.pipeline.stopAndProcess()
        try await fixture.finished()

        fixture.settings.sendWithShift = true
        fixture.keyboard.value = 0
        fixture.pipeline.startRecording(RecordingRequest(triggerUsesShift: true))
        try await waitUntil("second recording") { fixture.pipeline.isRecording }
        fixture.keyboard.value = Hotkey.maskShift
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(fixture.pipeline.sendLocked, "Shift is part of the shortcut")
        fixture.pipeline.cancel()
        XCTAssertEqual(fixture.probe.returns, 0)
    }

    /// A copy-only profile copies without pasting, a file profile appends and a missing
    /// folder blocks recording, and a profile shortcut uses its own profile.
    func testProfileOutputsCopyOrAppendAndProfileShortcutsUseTheirProfile() async throws {
        do {
            let fixture = try SpeedFixture(speech: "Remember to call Alex")
            defer { fixture.cleanUp() }
            fixture.setActiveProfile(output: .copy, sendsAutomatically: true)
            try await fixture.dictate()
            XCTAssertTrue(fixture.probe.insertedTexts.isEmpty)
            XCTAssertEqual(fixture.clipboard.string(forType: .string), "Remember to call Alex")
            XCTAssertEqual(fixture.probe.returns, 0, "Copy never sends")
            let record = try XCTUnwrap(fixture.history.recent().first)
            XCTAssertEqual(record.outputDestination, DictationRecord.copyDestination)
            XCTAssertEqual(record.deliveryStatus, .delivered)
        }

        do {
            let fixture = try SpeedFixture(speech: "Buy milk")
            defer { fixture.cleanUp() }
            let file = fixture.directory.appendingPathComponent("today.md")
            fixture.setActiveProfile(output: ProfileOutput(kind: .file, filePath: file.path), sendsAutomatically: false)
            try await fixture.dictate()
            XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "Buy milk\n")
            XCTAssertEqual(try fixture.history.recent().first?.outputDestination, DictationRecord.fileDestination)

            fixture.setActiveProfile(output: ProfileOutput(kind: .file, filePath: fixture.directory.appendingPathComponent("no/x.md").path),
                                     sendsAutomatically: false)
            let starts = fixture.recorder.startCount
            fixture.pipeline.startRecording()
            try await waitUntil("blocked") { fixture.probe.blocked > 0 }
            XCTAssertEqual(fixture.recorder.startCount, starts, "The microphone never opens")
        }

        let fixture = try SpeedFixture(speech: "Note for later")
        defer { fixture.cleanUp() }
        var notes = fixture.profiles.addNew()
        notes.output = .copy
        fixture.profiles.update(notes)
        fixture.pipeline.startRecording(RecordingRequest(profileID: notes.id))
        try await waitUntil("recording") { fixture.pipeline.isRecording }
        fixture.pipeline.stopAndProcess()
        try await fixture.finished()
        XCTAssertTrue(fixture.probe.insertedTexts.isEmpty)
        XCTAssertEqual(fixture.clipboard.string(forType: .string), "Note for later")
        XCTAssertEqual(try fixture.history.recent().first?.mode, notes.name)

        fixture.profiles.remove(id: notes.id)
        fixture.pipeline.startRecording(RecordingRequest(profileID: notes.id))
        try await waitUntil("deleted profile blocks") { fixture.probe.blocked > 0 }
    }

    /// Edit without a selection never opens the microphone; with one it rewrites the
    /// selection at the cursor without sending or flagging.
    func testEditRefusesWithoutSelectionAndRewritesItWithoutSendingOrFlagging() async throws {
        do {
            let fixture = try SpeedFixture(speech: "Make it formal", refiner: true)
            defer { fixture.cleanUp() }
            fixture.context.value = AppContext(bundleId: "com.apple.TextEdit", appName: "TextEdit", selectedText: nil, processID: 101)
            var failures: [String] = []
            fixture.pipeline.onStateChange = { if case .failed(let message) = $0 { failures.append(message) } }
            fixture.pipeline.startRecording(RecordingRequest(intent: .editSelection))
            try await waitUntil("refused") { !failures.isEmpty }
            XCTAssertEqual(fixture.recorder.startCount, 0)
        }

        let fixture = try SpeedFixture(speech: "Make it formal", refiner: true)
        defer { fixture.cleanUp() }
        fixture.setActiveProfile(output: .copy, sendsAutomatically: true)
        fixture.context.value = AppContext(bundleId: "com.apple.TextEdit", appName: "TextEdit", selectedText: "hey whats up", processID: 101)
        fixture.pipeline.startRecording(RecordingRequest(intent: .editSelection))
        try await waitUntil("recording") { fixture.pipeline.isRecording }
        XCTAssertEqual(fixture.pipeline.recordingBadge, DictationPipeline.editBadge(characters: 12))
        fixture.pipeline.stopAndProcess()
        try await fixture.finished()
        XCTAssertEqual(fixture.probe.insertedTexts, ["EDITED: hey whats up"], "Edits always replace the selection at the cursor")
        XCTAssertEqual(fixture.probe.returns, 0)
        XCTAssertNil(try fixture.history.recent().first?.flags)
    }

    func testIgnoredPressesAreCountedWhileProcessing() async throws {
        let fixture = try SpeedFixture(speech: "Counting words", speechDelay: 0.4)
        defer { fixture.cleanUp() }
        fixture.pipeline.startRecording()
        try await waitUntil("recording") { fixture.pipeline.isRecording }
        fixture.pipeline.stopAndProcess()
        try await waitUntil("processing") { fixture.pipeline.state == .transcribing || fixture.pipeline.state == .inserting }
        fixture.pipeline.startRecording()
        try await fixture.finished()
        let snapshot = await fixture.metrics.snapshot()
        XCTAssertEqual(snapshot.acceptedPresses, 1)
        XCTAssertEqual(snapshot.ignoredPresses, 1)
        XCTAssertEqual(snapshot.deliveries["com.openai.chat"]?.delivered, 1)
    }

    private func waitUntil(_ description: String, timeout: TimeInterval = 5,
                           file: StaticString = #filePath, line: UInt = #line,
                           condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail(description + " timed out", file: file, line: line)
        throw SpeedTestError.timedOut
    }
}

private enum SpeedTestError: Error { case timedOut }

@MainActor
private struct SpeedFixture {
    let suite: String
    let directory: URL
    let settings: AppSettings
    let history: HistoryStore
    let profiles: ProfileStore
    let recorder: SpeedTestRecorder
    let pipeline: DictationPipeline
    let probe: SpeedProbe
    let metrics: SpeedMetricsStore
    let keyboard = Locked<UInt64>(0)
    let context = Locked(AppContext.empty)
    /// Disposable: copy-only delivery never touches the user's clipboard.
    let clipboard = NSPasteboard.withUniqueName()

    init(speech: String, refiner: Bool = false, speechDelay: Double = 0) throws {
        suite = "airdraft.speed.\(UUID().uuidString)"
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        settings.asr = ASRConfig(kind: .parakeet)
        settings.llm = LLMConfig(kind: refiner ? .openAICompatible : .none)
        settings.useAppContext = false
        settings.livePreviewEnabled = false
        settings.outputDestination = .cursor
        history = try HistoryStore(directory: directory)
        let dictionary = DictionaryStore(directory: directory)
        recorder = SpeedTestRecorder()
        let probe = SpeedProbe()
        self.probe = probe
        let transcriber = SpeedSpeech(text: speech, delay: speechDelay)
        var refinerBuilder: (@Sendable (LLMConfig) -> (any Refiner)?)?
        if refiner { refinerBuilder = { _ in EchoEditRefiner() } }
        let factory = EngineFactory(status: EngineStatus(), credentialReader: { _ in nil },
                                    transcriberBuilder: { _ in transcriber }, refinerBuilder: refinerBuilder)
        profiles = ProfileStore(directory: directory)
        let context = self.context
        // An untrusted fake OS: the destination is ChatGPT's desktop app, with no field to read.
        let environment = TextInserter.Environment(
            frontmostApplication: { .init(processID: 101, bundleID: "com.openai.chat") },
            application: { _ in .init(processID: 101, bundleID: "com.openai.chat") },
            activate: { _ in true }, isTrusted: { false }, applicationFocus: { _ in nil }, systemFocus: { nil },
            focusedWindow: { _ in nil }, processID: { _ in nil }, readAttribute: { _, _ in (.failure, nil) },
            enableWebAccessibility: { _ in false }, postPaste: { false }, pasteboard: clipboard)
        pipeline = DictationPipeline(settings: settings, dictionary: dictionary, profiles: profiles, history: history,
            factory: factory, recorder: recorder,
            contextReader: AppContextReader(reading: { context.value }),
            inserter: TextInserter(environment: environment),
            insertText: { text, _, _ in
                probe.insert(text)
                return InsertionResult(method: .accessibility, notice: nil)
            },
            recordingPreflight: { _, _, _, _, _ in },
            requestMicrophoneAccess: { true })
        let keyboard = self.keyboard
        pipeline.modifierFlags = { keyboard.value }
        pipeline.pressReturn = { _ in probe.pressReturn(); return true }
        metrics = SpeedMetricsStore(directory: directory)
        pipeline.metrics = metrics
        pipeline.frontmostBundleID = { "com.openai.chat" }
        pipeline.onRecordingBlocked = { probe.block() }
    }

    func setActiveProfile(output: ProfileOutput?, sendsAutomatically: Bool) {
        var profile = profiles.activeProfile
        profile.output = output
        profile.sendsAutomatically = sendsAutomatically
        profiles.update(profile)
    }

    func dictate() async throws {
        pipeline.startRecording()
        let deadline = Date().addingTimeInterval(5)
        while !pipeline.isRecording, Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        pipeline.stopAndProcess()
        try await finished()
    }

    func finished() async throws {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if pipeline.lastOutcome != nil, !pipeline.isBusy, !pipeline.isFinishingDelivery { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Dictation did not finish")
        throw SpeedTestError.timedOut
    }

    func cleanUp() {
        pipeline.cancel()
        clipboard.releaseGlobally()
        try? history.close()
        try? FileManager.default.removeItem(at: directory)
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }
}

private final class SpeedProbe: Sendable {
    private let insertions = Locked<[String]>([])
    private let returnCount = Locked(0)
    private let blockedCount = Locked(0)
    var insertedTexts: [String] { insertions.value }
    var returns: Int { returnCount.value }
    var blocked: Int { blockedCount.value }
    func insert(_ text: String) { insertions.withLock { $0.append(text) } }
    func pressReturn() { returnCount.withLock { $0 += 1 } }
    func block() { blockedCount.withLock { $0 += 1 } }
}

/// Unchecked: driven only by the MainActor pipeline under test.
private final class SpeedTestRecorder: AudioRecording, @unchecked Sendable {
    var isRecording = false
    var startCount = 0
    var levelHandler: (@Sendable (Float) -> Void)?
    var interruptionHandler: (@Sendable (AudioRecorderError) -> Void)?
    func start(microphone: MicrophonePreference) throws {
        startCount += 1
        isRecording = true
    }
    func stop() -> [Float] { isRecording = false; return [Float](repeating: 0.125, count: 16_000) }
    func cancel() { isRecording = false }
}

private actor SpeedSpeech: Transcriber {
    nonisolated let id = "speed-test-speech"
    let text: String
    let delay: Double
    init(text: String, delay: Double) { self.text = text; self.delay = delay }
    func prepare() async throws {}
    func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        return Transcript(text: text, engine: id, latencyMs: 1)
    }
}

/// Returns the selection prefixed with EDITED, proving the Edit request carried it.
private final class EchoEditRefiner: Refiner, Sendable {
    let id = "speed-edit-refiner"
    func refine(_ request: RefineRequest) async throws -> RefineResult {
        RefineResult(text: "EDITED: " + (request.context.selectedText ?? "none"), engine: id, latencyMs: 0, promptVersion: "fixture")
    }
}
