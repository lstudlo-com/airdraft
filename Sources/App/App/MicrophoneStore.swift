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
        #if DEBUG
        if fixedForRender { return }
        #endif
        devices = MicrophoneDevices.available()
        systemDefaultID = MicrophoneDevices.systemDefaultID
    }

    #if DEBUG
    /// Fixed devices for offscreen renders, so this Mac's hardware cannot replace them.
    @ObservationIgnored private var fixedForRender = false
    func useRenderDevices(_ devices: [Microphone], systemDefaultID: AudioDeviceID?) {
        fixedForRender = true
        self.devices = devices
        self.systemDefaultID = systemDefaultID
    }
    #endif

    func selected(_ preference: MicrophonePreference) -> Microphone? {
        preference.resolve(in: devices, systemDefaultID: systemDefaultID)
    }

    func selection(_ preference: MicrophonePreference, preservingChannelFrom current: MicrophonePreference) -> MicrophonePreference {
        Self.selection(preference, preservingChannelFrom: current, devices: devices, systemDefaultID: systemDefaultID)
    }

    static func selection(_ preference: MicrophonePreference, preservingChannelFrom current: MicrophonePreference,
                          devices: [Microphone], systemDefaultID: AudioDeviceID?) -> MicrophonePreference {
        var next = preference
        if let device = current.resolve(in: devices, systemDefaultID: systemDefaultID),
           next.resolve(in: devices, systemDefaultID: systemDefaultID)?.uid == device.uid {
            next.channelIndex = current.channelIndex
        }
        return next
    }

    func label(_ preference: MicrophonePreference) -> String {
        selected(preference)?.name ?? "\(preference.name) · unavailable"
    }
}
