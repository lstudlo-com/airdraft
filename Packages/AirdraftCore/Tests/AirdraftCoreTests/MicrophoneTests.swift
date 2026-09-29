import XCTest
import CoreAudio
@testable import AirdraftCore

final class MicrophoneTests: XCTestCase {
    private let builtIn = Microphone(id: 1, uid: "built-in", name: "Mac microphone",
                                     transportType: kAudioDeviceTransportTypeBuiltIn)
    private let usb = Microphone(id: 2, uid: "usb-mic", name: "USB microphone",
                                 transportType: kAudioDeviceTransportTypeUSB)
    // Device names are user-editable; identification must use the transport.
    private let phone = Microphone(id: 3, uid: "phone", name: "Desk microphone",
                                   transportType: kAudioDeviceTransportTypeContinuityCaptureWireless)
    private let wiredPhone = Microphone(id: 4, uid: "wired-phone", name: "Other microphone",
                                        transportType: kAudioDeviceTransportTypeContinuityCaptureWired)

    func testOpeningDefaultPickerDoesNotPreviewUnselectedContinuityInputs() {
        let devices = [builtIn, phone, usb, wiredPhone]
        XCTAssertEqual(MicrophonePreference.systemDefault.levelPreviewDevices(in: devices, systemDefaultID: builtIn.id),
                       [builtIn, usb])
    }

    func testSelectingContinuityInputPreviewsOnlyThatPhone() {
        let devices = [builtIn, phone, usb, wiredPhone]
        for (selected, expected) in [(phone, [builtIn, phone, usb]), (wiredPhone, [builtIn, usb, wiredPhone])] {
            let preference = MicrophonePreference(uid: selected.uid, name: selected.name)
            XCTAssertEqual(preference.levelPreviewDevices(in: devices, systemDefaultID: builtIn.id),
                           expected)
        }
    }

    func testSwitchingAwayFromPhoneRemovesItFromPreviews() {
        let devices = [builtIn, phone, usb, wiredPhone]
        let preference = MicrophonePreference(uid: usb.uid, name: usb.name)
        XCTAssertEqual(preference.levelPreviewDevices(in: devices, systemDefaultID: phone.id), [builtIn, usb])
    }

    func testSystemDefaultPreviewsItsSelectedContinuityInputOnce() {
        let devices = [builtIn, phone, usb, wiredPhone]
        XCTAssertEqual(MicrophonePreference.systemDefault.levelPreviewDevices(in: devices, systemDefaultID: phone.id),
                       [builtIn, phone, usb])
        XCTAssertEqual(MicrophonePreference.systemDefault.levelPreviewDevices(in: devices, systemDefaultID: wiredPhone.id),
                       [builtIn, usb, wiredPhone])
    }

    func testUnavailableSelectionDoesNotPreviewAnotherContinuityInput() {
        let devices = [builtIn, usb, wiredPhone]
        let preference = MicrophonePreference(uid: phone.uid, name: phone.name)
        XCTAssertEqual(preference.levelPreviewDevices(in: devices, systemDefaultID: wiredPhone.id), [builtIn, usb])
        XCTAssertEqual(MicrophonePreference.systemDefault.levelPreviewDevices(in: devices, systemDefaultID: nil),
                       [builtIn, usb])
    }

    func testContinuityPreviewSelectionSurvivesDeviceIDChange() {
        let reconnected = Microphone(id: 93, uid: phone.uid, name: phone.name,
                                     transportType: phone.transportType)
        let preference = MicrophonePreference(uid: phone.uid, name: phone.name)
        XCTAssertEqual(preference.levelPreviewDevices(in: [builtIn, reconnected], systemDefaultID: builtIn.id),
                       [builtIn, reconnected])
    }

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
        let preference = MicrophonePreference(uid: usb.uid, name: usb.name, channelIndex: 1)
        settings.microphone = preference
        XCTAssertEqual(AppSettings(defaults: defaults).microphone, preference)
        settings.microphone = .systemDefault
        XCTAssertEqual(AppSettings(defaults: defaults).microphone, .systemDefault)
    }

    func testExistingMicrophonePreferenceDefaultsToFirstInput() throws {
        let data = Data(#"{"uid":"usb-mic","name":"USB microphone"}"#.utf8)
        let preference = try JSONDecoder().decode(MicrophonePreference.self, from: data)
        XCTAssertEqual(preference.uid, usb.uid)
        XCTAssertNil(preference.channelIndex)
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
