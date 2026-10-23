import AirdraftCore
import Foundation
import XCTest

/// An `AppContainer` built like `PreviewData.container` and the native-ui
/// fixture: a disposable settings file and data directory, injected
/// permissions and a dictation boundary that refuses to record or transcribe.
/// It is never started, so no hotkey, menu, HUD, updater or model work begins,
/// and nothing reads the user's preferences, history or Keychain.
@MainActor
final class IsolatedContainer {
    let container: AppContainer
    /// Holds the data directory and the preferences file; removed on tear-down.
    let root: URL

    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("airdraft-app-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // An absolute suite name keeps the settings file inside `root`, never
        // in ~/Library/Preferences.
        let defaults = UserDefaults(suiteName: root.appendingPathComponent("preferences").path)!
        let settings = AppSettings(defaults: defaults)
        container = AppContainer(
            settings: settings,
            dataDirectory: root.appendingPathComponent("data", isDirectory: true),
            recordingAccessCheck: { throw CancellationError() },
            permissions: SystemPermissions(checkAccessibility: { true }, checkMicrophone: { .authorized },
                                           promptAccessibility: { XCTFail("App tests never prompt for Accessibility") }),
            dictationBoundary: .init(recorder: AudioRecorder(),
                                     transcriberBuilder: { _ in preconditionFailure("App tests never transcribe") },
                                     recordingPreflight: { _, _, _, _, _ in throw CancellationError() },
                                     requestMicrophoneAccess: { false }))
        container.microphones.useRenderDevices([
            Microphone(id: 100, uid: "fixture-main", name: "Fixture Main", inputChannelCount: 2),
        ], systemDefaultID: 100)
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }
}
