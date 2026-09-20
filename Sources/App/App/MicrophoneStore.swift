import AirdraftCore
import CoreAudio
import Observation

@MainActor
@Observable
final class MicrophoneStore {
    private(set) var devices: [Microphone] = []
    private(set) var systemDefaultID: AudioDeviceID?
    @ObservationIgnored private var listener: AudioObjectPropertyListenerBlock?

    init() {
        refresh()
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        self.listener = listener
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
            var address = MicrophoneDevices.address(selector)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
    }

    deinit {
        guard let listener else { return }
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
            var address = MicrophoneDevices.address(selector)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
    }

    func refresh() {
        devices = MicrophoneDevices.available()
        systemDefaultID = MicrophoneDevices.systemDefaultID
    }

    func selected(_ preference: MicrophonePreference) -> Microphone? {
        preference.resolve(in: devices, systemDefaultID: systemDefaultID)
    }

    func label(_ preference: MicrophonePreference) -> String {
        selected(preference)?.name ?? "\(preference.name) · unavailable"
    }
}
