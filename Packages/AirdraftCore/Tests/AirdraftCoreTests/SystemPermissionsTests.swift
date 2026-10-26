import AVFoundation
import Observation
import XCTest
@testable import AirdraftCore

@MainActor
final class SystemPermissionsTests: XCTestCase {
    /// Grant and revocation refresh without restart or hotkey activity, and a fresh
    /// instance reads the current process rather than a previous grant.
    func testGrantAndRevocationRefreshAndFreshInstancesReadCurrentState() {
        var trusted = false
        var microphone: AVAuthorizationStatus = .notDetermined
        let permissions = SystemPermissions(checkAccessibility: { trusted }, checkMicrophone: { microphone })
        var transitions = 0
        permissions.accessibilityDidChange = { transitions += 1 }
        trusted = true
        microphone = .authorized
        permissions.refresh()
        XCTAssertTrue(permissions.accessibilityGranted)
        XCTAssertEqual(permissions.microphone, .authorized)
        permissions.refresh()
        XCTAssertEqual(transitions, 1)
        trusted = false
        microphone = .denied
        permissions.refresh()
        XCTAssertFalse(permissions.accessibilityGranted)
        XCTAssertEqual(permissions.microphone, .denied)
        XCTAssertEqual(transitions, 2)

        let previous = SystemPermissions(checkAccessibility: { true }, checkMicrophone: { .authorized })
        let replacement = SystemPermissions(checkAccessibility: { false }, checkMicrophone: { .denied })
        XCTAssertTrue(previous.accessibilityGranted)
        XCTAssertFalse(replacement.accessibilityGranted)
    }

    /// The prompt does not pretend permission was granted, and a permission change
    /// invalidates an observing view.
    func testPromptDoesNotPretendGrantAndChangesInvalidateObservers() {
        var prompts = 0
        var trusted = false
        let permissions = SystemPermissions(checkAccessibility: { trusted }, checkMicrophone: { .authorized },
                                            promptAccessibility: { prompts += 1 })
        permissions.requestAccessibility()
        XCTAssertEqual(prompts, 1)
        XCTAssertFalse(permissions.accessibilityGranted)
        trusted = true
        permissions.requestAccessibility()
        XCTAssertTrue(permissions.accessibilityGranted)
        XCTAssertEqual(prompts, 1)

        var observedTrusted = false
        let observed = SystemPermissions(checkAccessibility: { observedTrusted }, checkMicrophone: { .authorized })
        let changed = expectation(description: "SwiftUI observation invalidates")
        withObservationTracking {
            _ = observed.accessibilityGranted
        } onChange: {
            changed.fulfill()
        }
        observedTrusted = true
        observed.refresh()
        wait(for: [changed], timeout: 1)
    }
}
