import CoreAudio
import Foundation

public struct Microphone: Identifiable, Equatable, Sendable {
    public let id: AudioDeviceID
    public let uid: String
    public let name: String
    public let inputChannelCount: Int
    public let transportType: UInt32

    public init(id: AudioDeviceID, uid: String, name: String, inputChannelCount: Int = 1,
                transportType: UInt32 = kAudioDeviceTransportTypeUnknown) {
        self.id = id
        self.uid = uid
        self.name = name
        self.inputChannelCount = inputChannelCount
        self.transportType = transportType
    }

    public var isContinuity: Bool {
        transportType == kAudioDeviceTransportTypeContinuityCaptureWired ||
        transportType == kAudioDeviceTransportTypeContinuityCaptureWireless
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

    /// Opening a level meter establishes a Continuity connection. Only the
    /// selected input may do that, including a selected System Default alias.
    public func levelPreviewDevices(in devices: [Microphone], systemDefaultID: AudioDeviceID?) -> [Microphone] {
        let selectedUID = resolve(in: devices, systemDefaultID: systemDefaultID)?.uid
        return devices.filter { !$0.isContinuity || $0.uid == selectedUID }
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
            guard !isHidden(id), channels > 0, let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            // AVAudioEngine's private input bridge can appear during preview.
            // It disappears with its owner and is never a user-selectable input.
            guard !uid.hasPrefix("CADefaultDeviceAggregate-") && !name.hasPrefix("CADefaultDeviceAggregate-") else { return nil }
            return Microphone(id: id, uid: uid, name: name, inputChannelCount: channels,
                              transportType: transportType(id))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func isHidden(_ id: AudioDeviceID) -> Bool {
        var property = address(kAudioDevicePropertyIsHidden)
        var hidden: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &property, 0, nil, &size, &hidden) == noErr && hidden != 0
    }

    private static func transportType(_ id: AudioDeviceID) -> UInt32 {
        var property = address(kAudioDevicePropertyTransportType)
        var transport: UInt32 = kAudioDeviceTransportTypeUnknown
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &property, 0, nil, &size, &transport) == noErr else {
            return kAudioDeviceTransportTypeUnknown
        }
        return transport
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
