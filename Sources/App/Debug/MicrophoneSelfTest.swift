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
            let interruptions = CallbackCount()
            let buffers = CallbackCount()
            recorder.interruptionHandler = { _ in interruptions.increment() }
            recorder.levelHandler = { _ in buffers.increment() }
            let devices = MicrophoneDevices.available()
            log.notice("microphone-test: found \(devices.count) input devices")
            let environment = ProcessInfo.processInfo.environment
            var choices = [MicrophonePreference.systemDefault] + devices.map {
                MicrophonePreference(uid: $0.uid, name: $0.name)
            }
            if let name = environment["AIRDRAFT_MICROPHONE_TEST_DEVICE"] {
                choices = choices.filter { $0.name == name || $0.uid == name }
            }
            if let value = environment["AIRDRAFT_MICROPHONE_TEST_CHANNEL"], let channel = Int(value) {
                choices = choices.map { choice in
                    var choice = choice
                    choice.channelIndex = channel - 1
                    return choice
                }
            }
            let requireSignal = environment["AIRDRAFT_MICROPHONE_TEST_REQUIRE_SIGNAL"] == "1"
            let cycles = Int(ProcessInfo.processInfo.environment["AIRDRAFT_MICROPHONE_TEST_CYCLES"] ?? "") ?? 3
            var failures = choices.isEmpty ? 1 : 0
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
                        let buffersAfterRestart = buffers.value
                        try await Task.sleep(for: .milliseconds(250))
                        let resumedCapture = buffers.value > buffersAfterRestart
                        let samples = recorder.stop()
                        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
                        let captured = samples.count > Int(AudioRecorder.sampleRate * 1.1)
                        let uninterrupted = interruptions.value == initialInterruptions
                        let passed = selected && captured && resumed && resumedCapture && uninterrupted && (!requireSignal || peak > 0)
                        if !passed { failures += 1 }
                        log.notice("microphone-test: cycle=\(cycle) \(choice.name, privacy: .public) input=\((choice.channelIndex ?? 0) + 1) routeVerified=\(selected) resumed=\(resumed) resumedCapture=\(resumedCapture) uninterrupted=\(uninterrupted) samples=\(samples.count) peak=\(peak) \(passed ? "PASS" : "FAIL", privacy: .public)")
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

private final class CallbackCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); count += 1; lock.unlock() }
}
