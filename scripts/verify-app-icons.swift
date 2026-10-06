// Compile with AppIconController.swift and the built AirdraftCore framework.
// Usage: verify-app-icons /path/to/Airdraft\ Debug.app
// Uses a disposable preferences suite and its own NSApplication. No app services start.
import AppKit
import AirdraftCore

@main
struct AppIconVerification {
    @MainActor static func main() async throws {
        let bundle = Bundle(path: CommandLine.arguments[1])!
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.finishLaunching()
        let suite = "airdraft.icon-verification.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = AppSettings(defaults: defaults)
        application.appearance = NSAppearance(named: .aqua)
        var controller: AppIconController? = AppIconController(settings: settings, bundle: bundle)

        func pixels(_ image: NSImage) -> Data {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSGraphicsContext.current!.cgContext.clear(CGRect(x: 0, y: 0, width: 64, height: 64))
            image.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64))
            NSGraphicsContext.restoreGraphicsState()
            return Data(bytes: rep.bitmapData!, count: rep.bytesPerRow * rep.pixelsHigh)
        }

        func expect(_ style: AppIconStyle) async throws {
            fputs("Checking \(style.title)\n", stderr)
            guard let expected = bundle.image(forResource: NSImage.Name(style.assetName)) else {
                fatalError("Missing bundled icon: \(style.assetName)")
            }
            let candidates = AppIconStyle.allCases.map { candidate in
                (candidate, pixels(bundle.image(forResource: NSImage.Name(candidate.assetName))!))
            }
            for _ in 0..<100 {
                if let actual = application.applicationIconImage {
                    let observed = pixels(actual)
                    let distances = candidates.map { candidate, reference in
                        let error = zip(observed, reference).reduce(0.0) { result, pair in
                            result + abs(Double(pair.0) - Double(pair.1))
                        } / Double(reference.count)
                        return (candidate, error)
                    }
                    // AppKit round-trips icon color profiles, causing sub-byte rounding.
                    // Require both a close pixel match and the correct nearest artwork.
                    if let nearest = distances.min(by: { $0.1 < $1.1 }),
                       nearest.0 == style, nearest.1 < 2 { return }
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            let actual = application.applicationIconImage
            fputs("Icon mismatch: actual=\(String(describing: actual?.size)) expected=\(expected.size), appearance=\(application.effectiveAppearance.name.rawValue)\n", stderr)
            exit(1)
        }

        try await expect(.carvedWave)
        application.appearance = NSAppearance(named: .darkAqua)
        try await expect(.nightWave)
        for style in AppIconStyle.allCases {
            settings.appIcons.dark = style
            try await expect(style)
        }
        // Editing the inactive theme must not override the active icon.
        settings.appIcons.light = .pureWave
        try await Task.sleep(for: .milliseconds(60))
        try await expect(.nightWave)
        application.appearance = NSAppearance(named: .aqua)
        try await expect(.pureWave)
        for style in AppIconStyle.allCases {
            settings.appIcons.light = style
            try await expect(style)
        }
        settings.appIcons = AppIconPreferences(light: .pureWave, dark: .carvedWave)
        try await expect(.pureWave)
        controller = nil
        settings = AppSettings(defaults: defaults)
        application.appearance = NSAppearance(named: .darkAqua)
        controller = AppIconController(settings: settings, bundle: bundle)
        try await expect(.carvedWave)
        // nil is the real Auto path, resolved against this Mac's effective appearance.
        application.appearance = nil
        let systemIsDark = application.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        try await expect(settings.appIcons.icon(isDark: systemIsDark))
        withExtendedLifetime(controller) {}
        print("PASS: default light/dark icons, all choices in both themes, inactive preference isolation, restart persistence and Auto resolution")
    }
}
