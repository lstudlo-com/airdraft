import AirdraftCore
import Foundation

/// Offscreen renders (`--render-window`, Debug builds only). Views ask this
/// instead of reading process arguments; it is always off in Release.
enum RenderMode {
    /// Local E2E runs must never load, migrate, or edit provider credentials.
    static var excludesCredentials: Bool {
        #if DEBUG
        LocalE2E.isActive
        #else
        false
        #endif
    }
    #if DEBUG
    static let isActive = ProcessInfo.processInfo.arguments.contains("--render-window")
    /// `AIRDRAFT_RENDER_<key>`, only while rendering.
    static func value(_ key: String) -> String? {
        isActive ? ProcessInfo.processInfo.environment["AIRDRAFT_RENDER_\(key)"] : nil
    }
    /// `AIRDRAFT_RENDER_TEXT_SIZE=standard|large|larger` renders without changing saved settings.
    static var textSize: TextSizePreference? { value("TEXT_SIZE").flatMap(TextSizePreference.init(rawValue:)) }
    #else
    static let isActive = false
    static var textSize: TextSizePreference? { nil }
    static func value(_ key: String) -> String? { nil }
    #endif
}
