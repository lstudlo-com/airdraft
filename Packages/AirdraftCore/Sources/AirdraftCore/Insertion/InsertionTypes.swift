import Foundation

public enum InsertionMethod: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Legacy automatic setting; uses the same validated paste path as `paste`.
    case auto
    /// Always paste (clipboard is restored after confirmed delivery).
    case paste
    public var id: String { rawValue }
}

/// What the destination is known to have received.
public enum TextDeliveryStatus: String, Sendable, Codable, CaseIterable {
    /// The original field shows the text (or a script completed).
    case delivered
    /// One paste reached a validated editor that draws its own text and exposes
    /// none to read back (`TextInserter.drawsOwnText`: Warp, Zed, GPU terminals).
    /// Not a failure: there is simply nothing that could confirm it.
    case sentUnverified
    /// Nothing was sent, or a paste that could have been confirmed was not.
    case notDelivered
}

public struct InsertionResult: Sendable, Equatable {
    public enum Method: String, Sendable {
        case accessibility, paste, clipboardOnly
        /// Onboarding practice's own editor received the text directly.
        case practiceEditor
    }
    public let method: Method
    public let notice: String?
    /// Recovery messages stay readable; an intentional copy is only a confirmation.
    public var noticeRequiresAttention = true
    /// Why the text was copied instead of pasted, for History; the HUD shows only `notice`.
    public var detail: String?
    /// False only for a paste into a validated editor that draws its own text.
    public var isVerified = true
    public var delivery: TextDeliveryStatus {
        method == .clipboardOnly ? .notDelivered : (isVerified ? .delivered : .sentUnverified)
    }
    /// True only when the destination confirmed the text.
    public var didInsert: Bool { delivery == .delivered }
    /// True when the text reached the destination, confirmed or not.
    public var wasSent: Bool { delivery != .notDelivered }
}
