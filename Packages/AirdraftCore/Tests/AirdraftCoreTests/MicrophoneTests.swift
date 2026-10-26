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

    /// Level previews: the default picker skips unselected Continuity inputs, a selected
    /// phone previews only itself (and leaves when deselected), System Default previews
    /// its resolved phone once, an unavailable selection previews no other phone, and a
    /// selection survives a device ID change.
    func testLevelPreviewDevicesIncludeOnlySelectedOrDefaultContinuityInputs() {
        let devices = [builtIn, phone, usb, wiredPhone]
        XCTAssertEqual(MicrophonePreference.systemDefault.levelPreviewDevices(in: devices, systemDefaultID: builtIn.id),
                       [builtIn, usb], "default picker")

        for (selected, expected) in [(phone, [builtIn, phone, usb]), (wiredPhone, [builtIn, usb, wiredPhone])] {
            let preference = MicrophonePreference(uid: selected.uid, name: selected.name)
            XCTAssertEqual(preference.levelPreviewDevices(in: devices, systemDefaultID: builtIn.id),
                           expected, "selected \(selected.uid)")
        }

        let switchedAway = MicrophonePreference(uid: usb.uid, name: usb.name)
        XCTAssertEqual(switchedAway.levelPreviewDevices(in: devices, systemDefaultID: phone.id), [builtIn, usb],
                       "switched away from phone")

        XCTAssertEqual(MicrophonePreference.systemDefault.levelPreviewDevices(in: devices, systemDefaultID: phone.id),
                       [builtIn, phone, usb], "system default resolves to wireless phone")
        XCTAssertEqual(MicrophonePreference.systemDefault.levelPreviewDevices(in: devices, systemDefaultID: wiredPhone.id),
                       [builtIn, usb, wiredPhone], "system default resolves to wired phone")

        let withoutPhone = [builtIn, usb, wiredPhone]
        let unavailable = MicrophonePreference(uid: phone.uid, name: phone.name)
        XCTAssertEqual(unavailable.levelPreviewDevices(in: withoutPhone, systemDefaultID: wiredPhone.id), [builtIn, usb],
                       "unavailable selection")
        XCTAssertEqual(MicrophonePreference.systemDefault.levelPreviewDevices(in: withoutPhone, systemDefaultID: nil),
                       [builtIn, usb], "no system default")

        let reconnected = Microphone(id: 93, uid: phone.uid, name: phone.name,
                                     transportType: phone.transportType)
        XCTAssertEqual(unavailable.levelPreviewDevices(in: [builtIn, reconnected], systemDefaultID: builtIn.id),
                       [builtIn, reconnected], "reconnected phone with a new device ID")
    }

    /// A pinned device ignores the system default and survives a new device ID, a
    /// disconnected one never captures another microphone, and System Default follows
    /// the current route.
    func testPreferenceResolution() {
        let preference = MicrophonePreference(uid: usb.uid, name: usb.name)
        let reconnected = Microphone(id: 93, uid: usb.uid, name: usb.name)
        XCTAssertEqual(preference.resolve(in: [builtIn, reconnected], systemDefaultID: builtIn.id), reconnected)

        XCTAssertNil(preference.resolve(in: [builtIn], systemDefaultID: builtIn.id))
        XCTAssertEqual(preference.resolve(in: [builtIn, usb], systemDefaultID: builtIn.id), usb)

        XCTAssertEqual(MicrophonePreference.systemDefault.resolve(in: [builtIn, usb], systemDefaultID: usb.id), usb)
        XCTAssertNil(MicrophonePreference.systemDefault.resolve(in: [], systemDefaultID: nil))
    }

    /// Preferences persist, old settings use System Default and a saved preference
    /// without a channel decodes to the first input.
    @MainActor func testPreferencePersistsAndOldSettingsUseDefaults() throws {
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

        let data = Data(#"{"uid":"usb-mic","name":"USB microphone"}"#.utf8)
        let decoded = try JSONDecoder().decode(MicrophonePreference.self, from: data)
        XCTAssertEqual(decoded.uid, usb.uid)
        XCTAssertNil(decoded.channelIndex)
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
