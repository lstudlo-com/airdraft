import AppKit
import AirdraftCore
import CoreAudio
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
            let choices = [MicrophonePreference.systemDefault] + devices.map {
                MicrophonePreference(uid: $0.uid, name: $0.name)
            }
            let cycles = Int(ProcessInfo.processInfo.environment["AIRDRAFT_MICROPHONE_TEST_CYCLES"] ?? "") ?? 3
            var failures = 0
            for cycle in 1...max(1, cycles) {
                for choice in choices {
                    do {
                        try recorder.start(microphone: choice)
                        let selected = recorder.activeMicrophone.map { device in
                            route(recorder.inputRouteID, contains: device.id)
                        } ?? false
                        try await Task.sleep(for: .milliseconds(600))
                        let samples = recorder.stop()
                        let captured = samples.count > Int(AudioRecorder.sampleRate * 0.7)
                        if !selected || !captured { failures += 1 }
                        log.notice("microphone-test: cycle=\(cycle) \(choice.name, privacy: .public) routeVerified=\(selected) samples=\(samples.count) \(selected && captured ? "PASS" : "FAIL", privacy: .public)")
                    } catch {
                        recorder.cancel()
                        failures += 1
                        log.error("microphone-test: cycle=\(cycle) \(choice.name, privacy: .public) FAIL \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
            log.notice("microphone-test: complete attempts=\(max(1, cycles) * choices.count) failures=\(failures)")
            NSApp.terminate(nil)
        }
    }

    /// Read the actual Core Audio route instead of checking our own saved label.
    private static func route(_ route: AudioDeviceID?, contains device: AudioDeviceID) -> Bool {
        guard let route else { return false }
        if route == device { return true }
        var address = MicrophoneDevices.address(kAudioAggregateDevicePropertyActiveSubDeviceList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(route, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(route, &address, 0, nil, &size, &devices) == noErr else { return false }
        return devices.contains(device)
    }
}
