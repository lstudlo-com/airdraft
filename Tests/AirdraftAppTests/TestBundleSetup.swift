import Foundation

/// XCTest's principal class, created once before any test runs.
///
/// The app finds AirdraftCore's resource bundle through `Bundle.main`. This test
/// bundle runs inside `xctest` and links AirdraftCore as an embedded framework,
/// so neither `Bundle.main` nor the framework holds that bundle; Xcode copies it
/// into this bundle's Resources. SwiftPM's Debug resource accessor also searches
/// an explicit directory, set here before anything reads `Bundle.module`.
final class TestBundleSetup: NSObject {
    override init() {
        super.init()
        guard let resources = Bundle(for: TestBundleSetup.self).resourceURL,
              FileManager.default.fileExists(atPath: resources.appendingPathComponent("AirdraftCore_AirdraftCore.bundle").path)
        else { return }
        setenv("PACKAGE_RESOURCE_BUNDLE_PATH", resources.path, 1)
    }
}
