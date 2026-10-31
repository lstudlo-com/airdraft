import Foundation

#if !os(macOS)
/// iOS has no global shortcuts; the namespace keeps the saved trigger delay valid.
public enum HotkeyTriggerState {}
#endif

extension HotkeyTriggerState {
    public static let delayRange = 0...1000
    public static func clampedDelay(_ milliseconds: Int) -> Int {
        min(delayRange.upperBound, max(delayRange.lowerBound, milliseconds))
    }
}
