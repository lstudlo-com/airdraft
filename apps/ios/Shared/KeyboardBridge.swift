import Foundation

/// How the Airdraft keyboard and the app talk. A keyboard has no microphone, so
/// the app records and transcribes while the keyboard inserts the result.
///
/// State and the finished text live in the shared App Group defaults; Darwin
/// notifications, which carry no payload, only say that something changed.
/// Finished text stays there at most `Delivery.lifetime` and is removed as soon
/// as the keyboard has inserted it.
enum KeyboardBridge {
    enum Signal: String, CaseIterable, Sendable {
        /// Keyboard → app: start recording in the running session.
        case start = "com.lstudlo.app.airdraft.keyboard.start"
        /// Keyboard → app: stop recording and process it.
        case stop = "com.lstudlo.app.airdraft.keyboard.stop"
        /// Keyboard → app: discard the recording.
        case cancel = "com.lstudlo.app.airdraft.keyboard.cancel"
        /// Keyboard → app: the delivery was inserted (see `receipt`).
        case consumed = "com.lstudlo.app.airdraft.keyboard.consumed"
        /// App → keyboard: `state` or `delivery` changed.
        case state = "com.lstudlo.app.airdraft.app.state"
    }

    struct State: Codable, Equatable, Sendable {
        enum Phase: String, Codable, Sendable {
            /// No session: the keyboard asks the user to start one in Airdraft.
            case off
            /// The input is open in standby; the keyboard's microphone starts at once.
            case ready
            case recording
            case processing
        }

        var phase: Phase
        /// When the standby session closes.
        var endsAt: Date?
        var recordingStartedAt: Date?
        /// A problem the keyboard shows, such as missing setup.
        var message: String?
        var updatedAt: Date

        static let off = State(phase: .off, endsAt: nil, recordingStartedAt: nil, message: nil, updatedAt: .distantPast)

        /// Whether the app can serve a request now. A session whose end has
        /// passed, or an app that was closed without saying so, is not live.
        func isLive(at now: Date) -> Bool {
            guard phase != .off else { return false }
            guard let endsAt else { return false }
            return endsAt > now
        }
    }

    /// One press of the keyboard's microphone. Only the keyboard process that
    /// made the request inserts its delivery: text never lands in a field the
    /// user did not dictate into.
    struct Request: Codable, Equatable, Sendable, Identifiable {
        var id: UUID
        var createdAt: Date
    }

    struct Delivery: Codable, Equatable, Sendable, Identifiable {
        var id: UUID
        var requestID: UUID
        var text: String
        var createdAt: Date

        static let lifetime: TimeInterval = 60

        func isFresh(at now: Date) -> Bool { now.timeIntervalSince(createdAt) < Self.lifetime }
    }

    struct Receipt: Codable, Equatable, Sendable {
        var id: UUID
        /// The text field shows the inserted text.
        var confirmed: Bool
    }

    /// The shared values. Tests pass their own defaults suite.
    struct Store {
        let defaults: UserDefaults

        init?(defaults: UserDefaults? = AppGroup.defaults) {
            guard let defaults else { return nil }
            self.defaults = defaults
        }

        private enum Key: String {
            case state = "bridge.state"
            case request = "bridge.request"
            case delivery = "bridge.delivery"
            case receipt = "bridge.receipt"
        }

        var state: State {
            get { read(.state) ?? .off }
            nonmutating set { write(newValue, .state) }
        }

        var request: Request? {
            get { read(.request) }
            nonmutating set { write(newValue, .request) }
        }

        var delivery: Delivery? {
            get { read(.delivery) }
            nonmutating set { write(newValue, .delivery) }
        }

        var receipt: Receipt? {
            get { read(.receipt) }
            nonmutating set { write(newValue, .receipt) }
        }

        private func read<T: Decodable>(_ key: Key) -> T? {
            guard let data = defaults.data(forKey: key.rawValue) else { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        }

        private func write<T: Encodable>(_ value: T?, _ key: Key) {
            guard let value, let data = try? JSONEncoder().encode(value) else {
                defaults.removeObject(forKey: key.rawValue)
                return
            }
            defaults.set(data, forKey: key.rawValue)
        }
    }

    static func post(_ signal: Signal) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(signal.rawValue as CFString), nil, nil, true)
    }

    /// Whether the keyboard inserted `text`: the field before the cursor now ends with it.
    static func confirms(_ text: String, contextBeforeInput: String?) -> Bool {
        guard let context = contextBeforeInput, !text.isEmpty else { return false }
        // Fields may hold only the last part of a long document before the cursor.
        let tail = String(text.suffix(min(text.count, 40)))
        return context.hasSuffix(tail)
    }
}

/// Receives Darwin signals on the main actor until it is released.
@MainActor
final class DarwinSignalListener {
    private var handlers: [String: @MainActor () -> Void] = [:]

    init() {}

    func observe(_ signal: KeyboardBridge.Signal, _ handler: @escaping @MainActor () -> Void) {
        handlers[signal.rawValue] = handler
        let observer = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), observer, { _, observer, name, _, _ in
            guard let observer, let name = name?.rawValue as String? else { return }
            let address = UInt(bitPattern: observer)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let pointer = UnsafeRawPointer(bitPattern: address) else { return }
                    Unmanaged<DarwinSignalListener>.fromOpaque(pointer).takeUnretainedValue().fire(name)
                }
            }
        }, signal.rawValue as CFString, nil, .deliverImmediately)
    }

    private func fire(_ name: String) {
        handlers[name]?()
    }

    isolated deinit {
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                                UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque()))
    }
}
