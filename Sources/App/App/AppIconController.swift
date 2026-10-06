import AppKit
import AirdraftCore
import Observation

extension AppIconStyle {
    var assetName: String {
        switch self {
        case .pureWave: return "AppIconPureWave"
        case .carvedWave: return "AppIconCarvedWave"
        case .nightWave: return "AppIconNightWave"
        }
    }
}

/// Changes the running application's Dock icon without modifying its signed bundle.
/// Effective appearance also changes when macOS switches themes while Auto is selected.
@MainActor
final class AppIconController {
    private let settings: AppSettings
    private let application: NSApplication
    private let bundle: Bundle
    private var appearanceObservation: NSKeyValueObservation?
    private var appliedStyle: AppIconStyle?

    init(settings: AppSettings, application: NSApplication? = nil, bundle: Bundle = .main) {
        let application = application ?? .shared
        self.settings = settings
        self.application = application
        self.bundle = bundle
        appearanceObservation = application.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.update() }
        }
        observePreferences()
        update()
    }

    private func observePreferences() {
        withObservationTracking {
            _ = settings.appIcons
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observePreferences()
                self?.update()
            }
        }
    }

    private func update() {
        let isDark = application.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let style = settings.appIcons.icon(isDark: isDark)
        guard style != appliedStyle,
              let image = bundle.image(forResource: NSImage.Name(style.assetName)) else { return }
        application.applicationIconImage = image
        appliedStyle = style
    }
}
