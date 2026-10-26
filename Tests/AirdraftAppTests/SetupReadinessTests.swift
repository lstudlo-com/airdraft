import AirdraftCore
import XCTest

/// How Home's setup card, hero and sidebar footer map in-memory state to rows.
/// Facts are never measured here: unmeasured local files read as Checking.
@MainActor
final class SetupReadinessTests: XCTestCase {
    /// Runs `body` with a fresh isolated container and removes its data afterwards.
    private func withContainer(_ body: (AppContainer) throws -> Void) rethrows {
        let isolated = IsolatedContainer()
        defer { isolated.tearDown() }
        try body(isolated.container)
    }

    /// Each row with a fresh container: refinement off is inactive, an unmeasured local model is
    /// Checking, cloud speech without a key needs attention, the microphone needs its device and
    /// channel, and cursor output follows Accessibility while scripts wait for their check.
    func testReadinessRowsForRefinementSpeechMicrophoneAndOutput() {
        withContainer { container in
            container.settings.llm.select(.none)
            let readiness = container.readiness
            XCTAssertEqual(readiness.refinementTone, .inactive)
            XCTAssertEqual(readiness.refinementDetail, "Off · original transcript")
            XCTAssertFalse(readiness.refinementNeedsKey)
        }

        withContainer { container in
            container.settings.asr = ASRConfig(kind: .senseVoice, language: "en")
            let readiness = container.readiness
            XCTAssertEqual(readiness.speechTone, .busy)
            XCTAssertEqual(readiness.speechDetail, "Checking model files…")
            XCTAssertFalse(readiness.speechInstalled)
        }

        withContainer { container in
            container.settings.asr = ASRConfig(kind: .openAI, language: "en")
            XCTAssertNotNil(ASRProviderKind.openAI.preset)
            let readiness = container.readiness
            XCTAssertFalse(readiness.speechKeyPresent, "presence is never read in tests")
            XCTAssertEqual(readiness.speechTone, .attention)
            XCTAssertEqual(readiness.speechDetail, "API key missing or locked")
        }

        withContainer { container in
            let readiness = { container.readiness }
            container.settings.microphone = MicrophonePreference(uid: "fixture-main", name: "Fixture Main", channelIndex: 1)
            XCTAssertTrue(readiness().microphoneReady)
            XCTAssertEqual(readiness().microphoneDetail, "Fixture Main")

            container.settings.microphone = MicrophonePreference(uid: "fixture-main", name: "Fixture Main", channelIndex: 2)
            XCTAssertFalse(readiness().microphoneReady)
            XCTAssertEqual(readiness().microphoneDetail, "Selected input channel is unavailable")

            container.settings.microphone = MicrophonePreference(uid: "unplugged", name: "Unplugged")
            XCTAssertFalse(readiness().microphoneReady)
            XCTAssertEqual(readiness().microphoneDetail, "Selected microphone is unavailable")
        }

        withContainer { container in
            container.settings.outputDestination = .cursor
            XCTAssertTrue(container.readiness.outputReady)
            container.settings.outputDestination = .script
            container.settings.outputScriptPath = "/tmp/airdraft-app-tests/deliver.sh"
            let readiness = container.readiness
            XCTAssertEqual(readiness.scriptTone, .busy)
            XCTAssertEqual(readiness.scriptDetail, "Checking script…")
            // A script still being checked is not counted as a setup step.
            XCTAssertTrue(readiness.outputReady)
        }
    }

    /// A community build has no pipeline blockers; the summary and footer count setup steps.
    func testCommunityBuildHasNoBlockersAndSummaryAndFooterCountSetupSteps() {
        withContainer { container in
            let readiness = container.readiness
            XCTAssertTrue(readiness.blockers.isEmpty)
            XCTAssertNil(readiness.licenseBlocker)
            XCTAssertFalse(readiness.recordingsBlocked)
            XCTAssertFalse(readiness.footerOpensLicense)
        }

        withContainer { container in
            container.settings.asr = ASRConfig(kind: .openAI, language: "en")
            container.settings.llm.select(.none)
            container.settings.outputDestination = .cursor
            container.settings.microphone = MicrophonePreference(uid: "fixture-main", name: "Fixture Main", channelIndex: 0)
            let readiness = container.readiness
            // The container is never started, so the shortcut is inactive; the cloud key is missing.
            XCTAssertFalse(container.hotkeys.isActive)
            XCTAssertEqual(readiness.setupIssueCount, 2)
            XCTAssertEqual(readiness.issueCount, 2)
            XCTAssertEqual(readiness.summary, "2 setup steps need attention")
            XCTAssertEqual(String(localized: readiness.footerTitle), "Finish Setup")
        }
    }
}
