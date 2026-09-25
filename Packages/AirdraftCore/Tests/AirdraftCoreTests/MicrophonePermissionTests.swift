import AVFoundation
import XCTest
@testable import AirdraftCore

@MainActor
final class MicrophonePermissionTests: XCTestCase {
    func testConcurrentRequestsShareOnePrompt() async {
        let gate = PermissionGate()
        var prompts = 0
        let permission = MicrophonePermission(status: { .notDetermined }, prompt: {
            prompts += 1
            return await gate.wait()
        })
        let first = Task { await permission.request() }
        await gate.started()
        let second = Task { await permission.request() }
        await Task.yield()
        await gate.finish(true)
        let results = await (first.value, second.value)
        XCTAssertTrue(results.0 && results.1)
        XCTAssertEqual(prompts, 1)
    }

    func testKnownPermissionStatesNeverPrompt() async {
        for status in [AVAuthorizationStatus.authorized, .denied, .restricted] {
            let permission = MicrophonePermission(status: { status }, prompt: { XCTFail("Must not prompt"); return false })
            let granted = await permission.request()
            XCTAssertEqual(granted, status == .authorized)
        }
    }

    func testPassiveAccessibilityChecksNeverPrompt() {
        var prompts = 0
        let permissions = SystemPermissions(checkAccessibility: { false }, checkMicrophone: { .notDetermined },
                                            promptAccessibility: { prompts += 1 })
        permissions.startMonitoring()
        defer { permissions.stopMonitoring() }
        for _ in 0..<8 { permissions.refresh() }
        XCTAssertEqual(prompts, 0)
        XCTAssertFalse(permissions.accessibilityGranted)
    }

    func testReleaseAndCancelWhilePermissionIsPendingNeverStartCapture() async {
        for releaseShortcut in [true, false] {
            let gate = PermissionGate()
            let suite = "airdraft.permission-test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
            let recorder = AudioRecorder()
            let pipeline = DictationPipeline(settings: AppSettings(defaults: defaults),
                dictionary: DictionaryStore(directory: directory), profiles: ProfileStore(directory: directory),
                history: nil, factory: EngineFactory(status: EngineStatus()), recorder: recorder,
                recordingPreflight: { _, _, _, _, _ in },
                requestMicrophoneAccess: { await gate.wait() })
            pipeline.startRecording()
            pipeline.startRecording()
            await gate.started()
            if releaseShortcut { pipeline.stopAndProcess() } else { pipeline.cancel() }
            await gate.finish(true)
            // Allow the resumed MainActor task to observe cancellation.
            for _ in 0..<5 { await Task.yield() }
            XCTAssertEqual(pipeline.state, .idle)
            XCTAssertFalse(recorder.isRecording)
            let calls = await gate.calls
            XCTAssertEqual(calls, 1)
        }
    }
}

private actor PermissionGate {
    private var continuation: CheckedContinuation<Bool, Never>?
    private(set) var calls = 0
    func wait() async -> Bool {
        calls += 1
        return await withCheckedContinuation { continuation = $0 }
    }
    func started() async { while continuation == nil { await Task.yield() } }
    func finish(_ result: Bool) { continuation?.resume(returning: result); continuation = nil }
}
