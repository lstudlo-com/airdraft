import Foundation

/// The timer is an independent recording-window module, shared by every preset.
public struct HUDTimerOptions: Codable, Equatable, Sendable {
    public enum Position: String, Codable, CaseIterable, Sendable, Identifiable {
        case left, right
        public var id: String { rawValue }
        public var title: String { self == .left ? "Left" : "Right" }
    }

    public var isEnabled: Bool
    public var position: Position

    public init(isEnabled: Bool = false, position: Position = .right) {
        self.isEnabled = isEnabled
        self.position = position
    }
}
