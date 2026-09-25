import AirdraftCore
import Observation

/// One capture per device. The system-default row shares its device's level.
@MainActor
@Observable
final class MicrophoneLevelPreviews {
    private(set) var levels: [String: Float] = [:]
    private(set) var errors: [String: String] = [:]

    private struct Session {
        let device: Microphone
        let channel: Int
        let recorder: AudioRecorder
    }
    @ObservationIgnored private var sessions: [String: Session] = [:]

    func synchronize(devices: [Microphone], selection: MicrophonePreference, systemDefaultID: UInt32?) {
        let selected = selection.resolve(in: devices, systemDefaultID: systemDefaultID)
        let available = Set(devices.map(\.uid))
        for uid in Array(sessions.keys) where !available.contains(uid) { stop(uid) }
        errors = errors.filter { available.contains($0.key) }

        for device in devices {
            let channel = selected?.uid == device.uid ? selection.channelIndex ?? 0 : 0
            if let session = sessions[device.uid], session.device == device, session.channel == channel {
                continue
            }
            stop(device.uid)
            errors[device.uid] = nil
            let recorder = AudioRecorder()
            sessions[device.uid] = Session(device: device, channel: channel, recorder: recorder)
            recorder.levelHandler = { [weak self, weak recorder] level in
                Task { @MainActor [weak self, weak recorder] in
                    guard let self, let recorder,
                          self.sessions[device.uid]?.recorder === recorder else { return }
                    self.levels[device.uid] = level
                }
            }
            recorder.interruptionHandler = { [weak self, weak recorder] reason in
                Task { @MainActor [weak self, weak recorder] in
                    guard let self, let recorder,
                          self.sessions[device.uid]?.recorder === recorder else { return }
                    self.stop(device.uid)
                    self.errors[device.uid] = reason.localizedDescription
                }
            }
            do {
                try recorder.startLevelMonitoring(microphone: MicrophonePreference(
                    uid: device.uid, name: device.name, channelIndex: channel
                ))
            } catch {
                stop(device.uid)
                errors[device.uid] = error.localizedDescription
            }
        }
    }

    func stop() {
        for uid in Array(sessions.keys) { stop(uid) }
        errors.removeAll()
    }

    private func stop(_ uid: String) {
        // Remove first so queued audio callbacks cannot restore a stale level.
        let session = sessions.removeValue(forKey: uid)
        session?.recorder.cancel()
        levels[uid] = nil
    }
}
