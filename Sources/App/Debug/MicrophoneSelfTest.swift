import AppKit
import AVFoundation
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
            let notifications = RecordingNotificationCenter()
            let recorder = AudioRecorder(notifications: notifications)
            let interruptions = InterruptionCount()
            recorder.interruptionHandler = { _ in interruptions.increment() }
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
                        let initialInterruptions = interruptions.value
                        try recorder.start(microphone: choice)
                        let selected = recorder.activeMicrophone.map { device in
                            route(recorder.inputRouteID, contains: device.id)
                        } ?? false
                        try await Task.sleep(for: .milliseconds(600))
                        // A delayed configuration notification must not kill a healthy input.
                        notifications.postConfigurationChange()
                        try await Task.sleep(for: .milliseconds(200))
                        // Exercise a real engine restart without changing the Mac's audio devices.
                        notifications.engine?.stop()
                        notifications.postConfigurationChange()
                        try await Task.sleep(for: .milliseconds(400))
                        let resumed = notifications.engine?.isRunning == true
                        let samples = recorder.stop()
                        let captured = samples.count > Int(AudioRecorder.sampleRate * 1.1)
                        let uninterrupted = interruptions.value == initialInterruptions
                        let passed = selected && captured && resumed && uninterrupted
                        if !passed { failures += 1 }
                        log.notice("microphone-test: cycle=\(cycle) \(choice.name, privacy: .public) routeVerified=\(selected) resumed=\(resumed) uninterrupted=\(uninterrupted) samples=\(samples.count) \(passed ? "PASS" : "FAIL", privacy: .public)")
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

/// Captures only this self-test's engine; no system-wide route or format changes.
private final class RecordingNotificationCenter: NotificationCenter, @unchecked Sendable {
    weak var engine: AVAudioEngine?

    override func addObserver(forName name: NSNotification.Name?, object obj: Any?, queue: OperationQueue?,
                              using block: @escaping @Sendable (Notification) -> Void) -> NSObjectProtocol {
        if name == .AVAudioEngineConfigurationChange { engine = obj as? AVAudioEngine }
        return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue, using: block)
    }

    override func removeObserver(_ observer: Any) {
        NotificationCenter.default.removeObserver(observer)
    }

    func postConfigurationChange() {
        guard let engine else { return }
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: engine)
    }
}

private final class InterruptionCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); count += 1; lock.unlock() }
}
