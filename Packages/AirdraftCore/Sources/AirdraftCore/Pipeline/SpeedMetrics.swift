import CoreAudio
import Foundation

/// Local counters behind the AD-104 measurements: shortcut presses ignored while
/// a dictation was processing, and shortcut-to-capture time by input type. They
/// stay in `speed-metrics.json` in the data folder and are never sent anywhere;
/// `scripts/speed-metrics.py` and Settings read them.
public struct SpeedMetricsSnapshot: Codable, Sendable, Equatable {
    public struct CaptureSample: Codable, Sendable, Equatable {
        public var ms: Int
        public var transport: String
        public var at: Date
    }
    public var version = 1
    public var since: Date
    public var ignoredPresses = 0
    public var acceptedPresses = 0
    public var captureSamples: [CaptureSample] = []
    /// Cursor delivery outcomes by destination bundle ID: counts only, kept
    /// even when Read app context is off, never sent anywhere (gate 5).
    public var deliveries: [String: DeliveryCounts] = [:]

    public struct DeliveryCounts: Codable, Sendable, Equatable {
        public var delivered = 0
        public var sentUnverified = 0
        public var notDelivered = 0
        public var total: Int { delivered + sentUnverified + notDelivered }
    }

    public static let maximumSamples = 500
    public static let maximumDestinations = 200

    public init(since: Date = Date()) { self.since = since }

    private enum CodingKeys: String, CodingKey {
        case version, since, ignoredPresses, acceptedPresses, captureSamples, deliveries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        since = try container.decodeIfPresent(Date.self, forKey: .since) ?? Date()
        ignoredPresses = try container.decodeIfPresent(Int.self, forKey: .ignoredPresses) ?? 0
        acceptedPresses = try container.decodeIfPresent(Int.self, forKey: .acceptedPresses) ?? 0
        captureSamples = try container.decodeIfPresent([CaptureSample].self, forKey: .captureSamples) ?? []
        deliveries = try container.decodeIfPresent([String: DeliveryCounts].self, forKey: .deliveries) ?? [:]
    }

    /// Delivery outcomes summed over destinations whose bundle ID starts with a prefix.
    public func deliveries(matching prefixes: [String]) -> DeliveryCounts {
        deliveries.filter { id, _ in prefixes.contains { id.hasPrefix($0) } }.values.reduce(into: DeliveryCounts()) {
            $0.delivered += $1.delivered
            $0.sentUnverified += $1.sentUnverified
            $0.notDelivered += $1.notDelivered
        }
    }

    /// AI chats and agents whose read-back rate decides automatic sending (gate 5).
    public static let aiDestinationPrefixes = ["com.openai.chat", "com.anthropic.claudefordesktop"]
        + AppFamily.bundlePrefixes(for: [.code, .terminal])

    /// Ignored presses per 100 accepted ones; nil before any press.
    public var ignoredPerHundred: Double? {
        acceptedPresses > 0 ? Double(ignoredPresses) * 100 / Double(acceptedPresses) : nil
    }

    /// Median shortcut-to-capture milliseconds for one input type.
    public func medianCaptureMs(transport: String? = nil) -> Int? {
        let values = captureSamples.filter { transport == nil || $0.transport == transport }.map(\.ms).sorted()
        guard !values.isEmpty else { return nil }
        return values[values.count / 2]
    }
}

/// Serializes reads and writes of one metrics file off the main actor.
public actor SpeedMetricsStore {
    public static let filename = "speed-metrics.json"
    private let url: URL?
    private var cached: SpeedMetricsSnapshot?

    /// Nil writes nothing (tests and fixtures without a data folder).
    public init(directory: URL?) {
        url = directory?.appendingPathComponent(Self.filename)
    }

    public func snapshot() -> SpeedMetricsSnapshot {
        if let cached { return cached }
        let loaded = url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? Self.decoder.decode(SpeedMetricsSnapshot.self, from: $0) }
        let value = loaded ?? SpeedMetricsSnapshot()
        cached = value
        return value
    }

    public func noteAcceptedPress() { update { $0.acceptedPresses += 1 } }
    public func noteIgnoredPress() { update { $0.ignoredPresses += 1 } }

    public func noteDelivery(bundleID: String?, status: TextDeliveryStatus) {
        guard let bundleID, !bundleID.isEmpty else { return }
        update { metrics in
            guard metrics.deliveries[bundleID] != nil || metrics.deliveries.count < SpeedMetricsSnapshot.maximumDestinations else { return }
            var counts = metrics.deliveries[bundleID] ?? .init()
            switch status {
            case .delivered: counts.delivered += 1
            case .sentUnverified: counts.sentUnverified += 1
            case .notDelivered: counts.notDelivered += 1
            }
            metrics.deliveries[bundleID] = counts
        }
    }

    public func noteCapture(ms: Int, transport: String) {
        update { metrics in
            metrics.captureSamples.append(.init(ms: ms, transport: transport, at: Date()))
            if metrics.captureSamples.count > SpeedMetricsSnapshot.maximumSamples {
                metrics.captureSamples.removeFirst(metrics.captureSamples.count - SpeedMetricsSnapshot.maximumSamples)
            }
        }
    }

    /// Removes the counts with History: deletes the file and starts again
    /// without writing until the next count.
    public func clear() {
        cached = SpeedMetricsSnapshot()
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    private func update(_ change: (inout SpeedMetricsSnapshot) -> Void) {
        guard url != nil else { return }
        var value = snapshot()
        change(&value)
        cached = value
        write()
    }

    private func write() {
        guard let url, let cached, let data = try? Self.encoder.encode(cached) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// The kind of input the recording used, by Core Audio transport type.
    public nonisolated static func transportName(_ type: UInt32?) -> String {
        switch type {
        case kAudioDeviceTransportTypeBuiltIn: "builtIn"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: "bluetooth"
        case kAudioDeviceTransportTypeUSB: "usb"
        case kAudioDeviceTransportTypeContinuityCaptureWired, kAudioDeviceTransportTypeContinuityCaptureWireless: "continuity"
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate: "virtual"
        case nil, kAudioDeviceTransportTypeUnknown: "unknown"
        default: "other"
        }
    }

    /// Resolves the selected microphone's transport off the main actor.
    public nonisolated static func transport(for preference: MicrophonePreference) -> String {
        let device = preference.resolve(in: MicrophoneDevices.available(), systemDefaultID: MicrophoneDevices.systemDefaultID)
        return transportName(device?.transportType)
    }
}
