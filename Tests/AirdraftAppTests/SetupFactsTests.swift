import AirdraftCore
import Foundation
import Synchronization
import XCTest

/// Readiness facts are measured off the main actor and only read from memory
/// while views redraw. These tests inject the measurement, so nothing reads the
/// real model folder, PATH or Apple Intelligence.
@MainActor
final class SetupFactsTests: XCTestCase {
    private final class Calls: Sendable {
        let inputs = Mutex<[SetupFacts.Inputs]>([])
        let onMainThread = Mutex(false)
        var count: Int { inputs.withLock { $0.count } }
    }

    private let sense = ASRConfig(kind: .senseVoice, language: "en")
    private let whisper = ASRConfig(kind: .whisperKit, language: "en")
    private let cloud = ASRConfig(kind: .openAI, language: "en")
    private let off = LLMConfig(kind: .none)

    private func facts(installed: Bool = true, scriptIssue: String? = nil, calls: Calls = Calls()) -> SetupFacts {
        SetupFacts(measurer: { inputs in
            calls.inputs.withLock { $0.append(inputs) }
            if Thread.isMainThread { calls.onMainThread.withLock { $0 = true } }
            var values = SetupFacts.Values()
            values.speechInstalled = installed
            values.scriptIssue = inputs.scriptPath == nil ? nil : scriptIssue
            values.ruleSpeech = inputs.ruleSpeech.map { .init(config: $0, installed: installed) }
            return values
        }, measuresDuringRenders: false)
    }

    func testUnmeasuredLocalModelIsPendingNotMissing() {
        let calls = Calls()
        let facts = facts(calls: calls)
        let values = facts.values(for: .init(speech: sense, llm: off))
        XCTAssertEqual(values.pending, [.speech])
        XCTAssertFalse(values.speechInstalled)
        XCTAssertEqual(calls.count, 0, "reading values must never measure")
    }

    func testCloudSpeechNeedsNoMeasurement() {
        let values = facts().values(for: .init(speech: cloud, llm: off))
        XCTAssertTrue(values.speechInstalled)
        XCTAssertTrue(values.pending.isEmpty)
    }

    func testRefreshMeasuresOffTheMainActorOnce() async {
        let calls = Calls()
        let facts = facts(installed: true, calls: calls)
        let inputs = SetupFacts.Inputs(speech: sense, llm: off)
        await facts.refresh(inputs)
        XCTAssertEqual(calls.count, 1)
        XCTAssertFalse(calls.onMainThread.withLock { $0 })
        let values = facts.values(for: inputs)
        XCTAssertTrue(values.speechInstalled)
        XCTAssertTrue(values.pending.isEmpty)
        // An identical result does not add another measurement.
        await facts.refresh(inputs)
        XCTAssertEqual(facts.measurements.count, 1)
    }

    func testSwitchingBackShowsTheLastKnownFacts() async {
        let facts = facts(installed: true)
        let first = SetupFacts.Inputs(speech: sense, llm: off)
        let second = SetupFacts.Inputs(speech: whisper, llm: off)
        await facts.refresh(first)
        await facts.refresh(second)
        XCTAssertEqual(facts.measurements.map { $0.inputs }, [second, first])
        XCTAssertTrue(facts.values(for: first).pending.isEmpty)
        XCTAssertTrue(facts.values(for: first).speechInstalled)
    }

    func testFactsWithUnchangedInputsCarryOverToNewInputs() async {
        let facts = facts(installed: true, scriptIssue: "Script is not executable")
        await facts.refresh(.init(speech: sense, scriptPath: "/tmp/deliver.sh", llm: off))
        // A different model with the same script: the script fact is known, the model is not.
        let values = facts.values(for: .init(speech: whisper, scriptPath: "/tmp/deliver.sh", llm: off))
        XCTAssertEqual(values.pending, [.speech])
        XCTAssertEqual(values.scriptIssue, "Script is not executable")
        // A different script is still being checked.
        let other = facts.values(for: .init(speech: sense, scriptPath: "/tmp/other.sh", llm: off))
        XCTAssertEqual(other.pending, [.script])
        XCTAssertNil(other.scriptIssue)
        XCTAssertTrue(other.speechInstalled)
    }

    func testRuleModelsReuseAnyMeasurementOfTheSameModel() async {
        let facts = facts(installed: true)
        await facts.refresh(.init(speech: whisper, llm: off))
        let values = facts.values(for: .init(speech: sense, llm: off, ruleSpeech: [whisper]))
        XCTAssertEqual(values.ruleSpeechInstalled(whisper), true)
        XCTAssertEqual(values.pending, [.speech])
        let unmeasured = facts.values(for: .init(speech: whisper, llm: off, ruleSpeech: [sense]))
        XCTAssertEqual(unmeasured.pending, [.ruleSpeech])
        XCTAssertNil(unmeasured.ruleSpeechInstalled(sense))
    }

    func testOnlyTheEightNewestMeasurementsAreKept() async {
        let facts = facts(installed: true)
        let inputs = (0..<9).map { SetupFacts.Inputs(speech: sense, scriptPath: "/tmp/script-\($0).sh", llm: off) }
        for input in inputs { await facts.refresh(input) }
        XCTAssertEqual(facts.measurements.count, 8)
        XCTAssertEqual(facts.measurements.first?.inputs, inputs[8])
        XCTAssertFalse(facts.measurements.contains { $0.inputs == inputs[0] })
    }

    func testAnOlderRefreshCannotReplaceANewerOne() async {
        let gate = DispatchSemaphore(value: 0)
        let calls = Calls()
        let slow = SetupFacts.Inputs(speech: sense, llm: off)
        let fast = SetupFacts.Inputs(speech: whisper, llm: off)
        let facts = SetupFacts(measurer: { inputs in
            calls.inputs.withLock { $0.append(inputs) }
            if inputs == slow { gate.wait() }
            var values = SetupFacts.Values()
            values.speechInstalled = true
            return values
        }, measuresDuringRenders: false)
        let older = Task { await facts.refresh(slow) }
        // The older refresh is measuring before the newer one starts.
        for _ in 0..<200 where calls.count == 0 { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(calls.count, 1)
        await facts.refresh(fast)
        gate.signal()
        await older.value
        XCTAssertEqual(facts.measurements.map { $0.inputs }, [fast])
        XCTAssertEqual(facts.values(for: slow).pending, [.speech])
    }

    /// Settings' Preview model row (AD-084) reads only measured facts: a
    /// redraw never stats the model folder, and an unmeasured model is Checking.
    func testModelPreviewReadinessReadsOnlyMeasuredFacts() async {
        let calls = Calls()
        let missing = facts(installed: false, calls: calls)
        let inputs = SetupFacts.Inputs(speech: sense, llm: off)
        XCTAssertEqual(ModelPreviewReadiness.of(sense, facts: missing.values(for: inputs)), .checking)
        guard case .unavailable(let unsupported) = ModelPreviewReadiness.of(whisper, facts: missing.values(for: .init(speech: whisper, llm: off))) else {
            return XCTFail("An unsupported model needs no measurement to be unavailable")
        }
        XCTAssertTrue(unsupported.contains(whisper.displayName))
        XCTAssertEqual(calls.count, 0, "Reading readiness must never measure")
        await missing.refresh(inputs)
        guard case .unavailable(let install) = ModelPreviewReadiness.of(sense, facts: missing.values(for: inputs)) else {
            return XCTFail("A measured missing model asks for installation")
        }
        XCTAssertEqual(install, ModelSpeechPreview.unavailableReason(for: sense, installed: false))
        let installed = facts(installed: true)
        await installed.refresh(inputs)
        XCTAssertEqual(ModelPreviewReadiness.of(sense, facts: installed.values(for: inputs)), .ready)
        XCTAssertEqual(calls.count, 1)
    }

    func testContainerPreviewReadinessIsCheckingUntilMeasured() {
        let isolated = IsolatedContainer()
        defer { isolated.tearDown() }
        isolated.container.settings.asr = sense
        XCTAssertEqual(isolated.container.modelPreviewReadiness, .checking,
                       "An unstarted container has measured nothing and must not stat files on read")
    }
}
