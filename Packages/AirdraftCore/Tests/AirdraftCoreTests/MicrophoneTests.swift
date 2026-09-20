import XCTest
@testable import AirdraftCore

final class MicrophoneTests: XCTestCase {
    private let builtIn = Microphone(id: 1, uid: "built-in", name: "Mac microphone")
    private let usb = Microphone(id: 2, uid: "usb-mic", name: "USB microphone")

    func testPinnedDeviceIgnoresSystemDefaultAndSurvivesNewDeviceID() {
        let preference = MicrophonePreference(uid: usb.uid, name: usb.name)
        let reconnected = Microphone(id: 93, uid: usb.uid, name: usb.name)
        XCTAssertEqual(preference.resolve(in: [builtIn, reconnected], systemDefaultID: builtIn.id), reconnected)
    }

    func testDisconnectedDeviceDoesNotSilentlyCaptureAnotherMicrophone() {
        let preference = MicrophonePreference(uid: usb.uid, name: usb.name)
        XCTAssertNil(preference.resolve(in: [builtIn], systemDefaultID: builtIn.id))
        XCTAssertEqual(preference.resolve(in: [builtIn, usb], systemDefaultID: builtIn.id), usb)
    }

    func testSystemDefaultFollowsCurrentRoute() {
        XCTAssertEqual(MicrophonePreference.systemDefault.resolve(in: [builtIn, usb], systemDefaultID: usb.id), usb)
        XCTAssertNil(MicrophonePreference.systemDefault.resolve(in: [], systemDefaultID: nil))
    }

    @MainActor func testPreferencePersistsAndOldSettingsUseSystemDefault() {
        let suite = "airdraft.microphone-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.microphone, .systemDefault)
        let preference = MicrophonePreference(uid: usb.uid, name: usb.name)
        settings.microphone = preference
        XCTAssertEqual(AppSettings(defaults: defaults).microphone, preference)
        settings.microphone = .systemDefault
        XCTAssertEqual(AppSettings(defaults: defaults).microphone, .systemDefault)
    }

    func testFailedStartCanBeRetriedAndStopIsSafe() {
        let recorder = AudioRecorder()
        let missing = MicrophonePreference(uid: UUID().uuidString, name: "Disconnected microphone")
        for _ in 0..<2 {
            XCTAssertThrowsError(try recorder.start(microphone: missing)) { error in
                guard case AudioRecorderError.microphoneUnavailable = error else {
                    return XCTFail("Expected unavailable microphone, received \(error)")
                }
            }
            XCTAssertFalse(recorder.isRecording)
            XCTAssertTrue(recorder.stop().isEmpty)
        }
    }
}
