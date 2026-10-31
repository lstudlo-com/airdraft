import Foundation

/// The App Group the app, the keyboard and the widgets share. The keyboard
/// reaches it only while the user allows Full Access.
enum AppGroup {
    static let identifier = "group.com.lstudlo.app.airdraft"

    static var defaults: UserDefaults? { UserDefaults(suiteName: identifier) }
}
