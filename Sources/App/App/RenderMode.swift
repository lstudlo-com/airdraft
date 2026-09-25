import Foundation

/// Offscreen renders (`--render-window`, Debug builds only). Views ask this
/// instead of reading process arguments; it is always off in Release.
enum RenderMode {
    #if DEBUG
    static let isActive = ProcessInfo.processInfo.arguments.contains("--render-window")
    /// `AIRDRAFT_RENDER_<key>`, only while rendering.
    static func value(_ key: String) -> String? {
        isActive ? ProcessInfo.processInfo.environment["AIRDRAFT_RENDER_\(key)"] : nil
    }
    #else
    static let isActive = false
    static func value(_ key: String) -> String? { nil }
    #endif
}
