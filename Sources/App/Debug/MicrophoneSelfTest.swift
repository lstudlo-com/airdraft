import AppKit
import AirdraftCore
import os

@MainActor
enum MicrophoneSelfTest {
    static func run() {
        Task {
            let log = Logger(subsystem: "com.lightiichen.airdraft", category: "microphone-test")
            guard await AudioRecorder.requestMicrophoneAccess() else {
                log.error("microphone-test: FAIL permission denied")
                NSApp.terminate(nil)
                return
            }
            let recorder = AudioRecorder()
            let devices = MicrophoneDevices.available()
            log.notice("microphone-test: found \(devices.count) input devices")
            for device in devices {
                do {
                    try recorder.start(microphone: MicrophonePreference(uid: device.uid, name: device.name))
                    let selected = recorder.activeMicrophone?.id == device.id
                    try await Task.sleep(for: .seconds(2))
                    let samples = recorder.stop()
                    let captured = samples.count > Int(AudioRecorder.sampleRate)
                    log.notice("microphone-test: \(device.name, privacy: .public) selected=\(selected) samples=\(samples.count) \(selected && captured ? "PASS" : "FAIL", privacy: .public)")
                } catch {
                    recorder.cancel()
                    log.error("microphone-test: \(device.name, privacy: .public) FAIL \(error.localizedDescription, privacy: .public)")
                }
            }
            NSApp.terminate(nil)
        }
    }
}
