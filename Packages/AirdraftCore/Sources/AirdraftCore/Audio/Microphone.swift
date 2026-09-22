import CoreAudio
import Foundation

public struct Microphone: Identifiable, Equatable, Sendable {
    public let id: AudioDeviceID
    public let uid: String
    public let name: String
    public let inputChannelCount: Int

    public init(id: AudioDeviceID, uid: String, name: String, inputChannelCount: Int = 1) {
        self.id = id
        self.uid = uid
        self.name = name
        self.inputChannelCount = inputChannelCount
    }
}

/// A device UID survives restarts and reconnects; its numeric device ID does not.
public struct MicrophonePreference: Codable, Equatable, Sendable {
    public var uid: String?
    public var name: String
    /// Zero-based hardware input. Older preferences use the first input.
    public var channelIndex: Int?
    public static let systemDefault = MicrophonePreference(uid: nil, name: "System default")

    public init(uid: String?, name: String, channelIndex: Int? = nil) {
        self.uid = uid
        self.name = name
        self.channelIndex = channelIndex
    }

    public func resolve(in devices: [Microphone], systemDefaultID: AudioDeviceID?) -> Microphone? {
        if let uid { return devices.first { $0.uid == uid } }
        return devices.first { $0.id == systemDefaultID }
    }
}

public enum MicrophoneDevices {
    /// AVAudioEngine can wrap the selected input in a private aggregate device.
    public static func route(_ route: AudioDeviceID, contains device: AudioDeviceID) -> Bool {
        if route == device { return true }
        var address = address(kAudioAggregateDevicePropertyActiveSubDeviceList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(route, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(route, &address, 0, nil, &size, &devices) == noErr else { return false }
        return devices.contains(device)
    }

    public static var systemDefaultID: AudioDeviceID? {
        var address = address(kAudioHardwarePropertyDefaultInputDevice)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    public static func available() -> [Microphone] {
        var address = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            let channels = inputChannelCount(id)
            guard channels > 0, let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            return Microphone(id: id, uid: uid, name: name, inputChannelCount: channels)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value as String
    }

    private static func inputChannelCount(_ id: AudioDeviceID) -> Int {
        var address = address(kAudioDevicePropertyStreamConfiguration)
        address.mScope = kAudioDevicePropertyScopeInput
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let data = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { data.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, data) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(data.assumingMemoryBound(to: AudioBufferList.self))
            .reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
