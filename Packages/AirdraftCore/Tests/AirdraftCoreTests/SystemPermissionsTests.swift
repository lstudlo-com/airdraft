import AVFoundation
import Observation
import XCTest
@testable import AirdraftCore

@MainActor
final class SystemPermissionsTests: XCTestCase {
    func testGrantAndRevocationRefreshWithoutRestartOrHotkeyActivity() {
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
    }

    func testPromptDoesNotPretendPermissionWasGranted() {
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
    }

    func testPermissionChangeInvalidatesAnObservingView() {
        var trusted = false
        let permissions = SystemPermissions(checkAccessibility: { trusted }, checkMicrophone: { .authorized })
        let changed = expectation(description: "SwiftUI observation invalidates")
        withObservationTracking {
            _ = permissions.accessibilityGranted
        } onChange: {
            changed.fulfill()
        }
        trusted = true
        permissions.refresh()
        wait(for: [changed], timeout: 1)
    }

    func testFreshInstanceReadsCurrentProcessRatherThanPreviousGrant() {
        let previous = SystemPermissions(checkAccessibility: { true }, checkMicrophone: { .authorized })
        let replacement = SystemPermissions(checkAccessibility: { false }, checkMicrophone: { .denied })
        XCTAssertTrue(previous.accessibilityGranted)
        XCTAssertFalse(replacement.accessibilityGranted)
    }
}
