#if DEBUG
import AppKit

/// AppKit's informal attribute API (`accessibilitySetValue:forAttribute:`,
/// `accessibilityAttributeNames`, `accessibilityAttributeValue:`), which the
/// Swift overlay marks deprecated since macOS 10.10. The NSAccessibility
/// protocol has no replacement for these two fixture needs: it cannot set
/// `AXEnhancedUserInterface` on the app, and some AppKit elements (outline
/// rows) still answer only the attribute API. The fixtures send the same
/// Objective-C messages by selector, so behavior matches the old direct calls.
enum LegacyAccessibility {
    /// Asks AppKit and SwiftUI to build their full accessibility tree, as they
    /// do for VoiceOver, without starting an assistive app.
    @MainActor
    static func enableEnhancedUserInterface() {
        _ = NSApp.perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"),
                          with: NSNumber(value: true), with: "AXEnhancedUserInterface" as NSString)
    }

    /// The attribute's value when `object` lists it in the legacy attribute
    /// names, otherwise nil.
    @MainActor
    static func value(of object: NSObject, attribute name: String) -> Any? {
        let names = NSSelectorFromString("accessibilityAttributeNames")
        let value = NSSelectorFromString("accessibilityAttributeValue:")
        guard object.responds(to: names), object.responds(to: value),
              let listed = object.perform(names)?.takeUnretainedValue() as? [String],
              listed.contains(name) else { return nil }
        return object.perform(value, with: name as NSString)?.takeUnretainedValue()
    }
}
#endif
