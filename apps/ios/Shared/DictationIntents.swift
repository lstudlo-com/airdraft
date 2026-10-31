import AppIntents
import Foundation

/// What a control, a shortcut or the Action Button asks the app to do. The
/// intents open Airdraft and hand the action to the running app.
enum DictationAction: Sendable {
    case dictate
    case startKeyboardSession
}

/// Hands intents to the app. An action that arrives before the app has set
/// its handler (a cold launch from a control) waits for it.
@MainActor
final class DictationIntentRouter {
    static let shared = DictationIntentRouter()

    private var pending: DictationAction?
    var handler: (@MainActor (DictationAction) -> Void)? {
        didSet {
            guard let handler, let action = pending else { return }
            pending = nil
            handler(action)
        }
    }

    func run(_ action: DictationAction) {
        if let handler { handler(action) } else { pending = action }
    }
}

struct StartDictationIntent: AppIntent {
    static let title = LocalizedStringResource("Start Dictation", table: "Shared")
    static let description = IntentDescription(LocalizedStringResource("Opens Airdraft and starts recording.", table: "Shared"))
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DictationIntentRouter.shared.run(.dictate)
        return .result()
    }
}

struct StartKeyboardSessionIntent: AppIntent {
    static let title = LocalizedStringResource("Start Keyboard Session", table: "Shared")
    static let description = IntentDescription(LocalizedStringResource("Keeps Airdraft listening for the Airdraft keyboard for a while.", table: "Shared"))
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DictationIntentRouter.shared.run(.startKeyboardSession)
        return .result()
    }
}
