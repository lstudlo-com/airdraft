#!/usr/bin/env python3
"""Compile and exercise native app behaviors without opening real app data.

Uses the production hotkey backends, microphone selection and HUD controller/views.
Core value types are compiled directly; permissions and the pipeline are fixtures.
No models, credentials, preferences, recordings or history are read. Copy uses a
disposable pasteboard, never the user's clipboard.
The HUD check briefly shows its own nonactivating panel. Run it between UI tests,
or use --skip-hud while another process owns the screen.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import tempfile


REPO = Path(__file__).resolve().parents[1]


def source(relative: str) -> str:
    # The required AirdraftCore types are compiled from their real source below.
    return (REPO / relative).read_text().replace("import AirdraftCore\n", "")


HOTKEY_FIXTURE = r'''
import AppKit
import AVFoundation

@MainActor final class SystemPermissions {
    var didRefresh: (() -> Void)?
    var accessibilityGranted = false
}

enum AppIdentity { static let logSubsystem = "com.lstudlo.airdraft.test.hotkeys" }

@main struct HotkeySuspensionCheck {
    @MainActor static func main() {
        _ = NSApplication.shared
        let service = HotkeyService(permissions: SystemPermissions())
        let modifiers = Hotkey.maskCommand | Hotkey.maskAlternate | Hotkey.maskControl | Hotkey.maskShift
        // No events are sent. Registration contention proves Carbon releases
        // the recorder's input without invoking microphone capture or dictation.
        let original = Hotkey(keyCode: 80, modifiers: modifiers)
        let replacement = Hotkey(keyCode: 79, modifiers: modifiers)
        let probe = CarbonHotkey()
        service.apply(original)
        precondition(service.backend == .carbon && service.isActive,
                     "Fixture shortcut unavailable: Control+Option+Shift+Command+F19")
        precondition(!probe.register(original), "Probe must not steal a registered shortcut")
        service.suspended = true
        precondition(probe.register(original), "Paused shortcut must be released to the recorder")
        probe.unregister()
        precondition(!service.isActive, "Recorder must pause the shortcut service")
        service.apply(replacement)
        precondition(!service.isActive, "Applying a shortcut must not resume an active recorder")
        precondition(probe.register(replacement), "Replacement must stay free during recording")
        probe.unregister()
        service.suspended = false
        precondition(service.backend == .carbon && service.isActive,
                     "Replacement must register when the recorder closes")
        precondition(!probe.register(replacement), "Replacement must now belong to the service")
        precondition(probe.register(original), "Original shortcut must remain available")
        probe.unregister()
        service.suspended = true
        service.suspended = true
        precondition(probe.register(replacement), "Repeated suspension must remain safe")
        probe.unregister()
        print("PASS: Carbon suspension, delayed replacement, resume and original shortcut release")
    }
}
'''


MICROPHONE_FIXTURE = r'''
import Foundation

@main struct MicrophoneSelectionCheck {
    @MainActor static func main() {
        let primary = Microphone(id: 10, uid: "fixture-main", name: "Two-input interface", inputChannelCount: 2)
        let other = Microphone(id: 20, uid: "fixture-other", name: "Built-in microphone")
        let devices = [primary, other]
        func select(_ next: MicrophonePreference, from current: MicrophonePreference,
                    defaultID: UInt32? = 10) -> MicrophonePreference {
            MicrophoneStore.selection(next, preservingChannelFrom: current,
                                      devices: devices, systemDefaultID: defaultID)
        }
        var automatic = MicrophonePreference.systemDefault
        automatic.channelIndex = 1
        let named = MicrophonePreference(uid: primary.uid, name: primary.name)
        let chosen = select(named, from: automatic)
        precondition(chosen.uid == primary.uid && chosen.channelIndex == 1,
                     "System Default to the same named input must preserve Input 2")
        let back = select(.systemDefault, from: chosen)
        precondition(back.uid == nil && back.channelIndex == 1,
                     "Named input to the same System Default must preserve Input 2")
        precondition(select(named, from: chosen).channelIndex == 1,
                     "Repeated device selection must preserve its channel")
        let distinct = MicrophonePreference(uid: other.uid, name: other.name)
        precondition(select(distinct, from: chosen).channelIndex == nil,
                     "A different physical input starts with its own default channel")
        precondition(select(.systemDefault, from: chosen, defaultID: 20).channelIndex == nil,
                     "A changed system route must not inherit an unrelated channel")
        let missing = MicrophonePreference(uid: "fixture-missing", name: "Missing input", channelIndex: 5)
        precondition(select(named, from: missing).channelIndex == nil,
                     "A missing old device cannot donate a channel")
        precondition(select(.systemDefault, from: chosen, defaultID: nil).channelIndex == nil,
                     "An unavailable default route cannot inherit a channel")
        print("PASS: same-route channel preservation, distinct/default-changed/unavailable route reset")
    }
}
'''


HUD_FIXTURE = r'''
import AppKit
import Foundation
import Observation
import SwiftUI

enum AppIdentity { static let logSubsystem = "com.lstudlo.airdraft.test.hud" }
enum HUDStyle: String { case mini, cube, sonic, none }

@MainActor @Observable final class DictationPipeline {
    static let levelHistoryLength = 22
    var state: PipelineState = .idle
    var isRecording: Bool { state == .recording }
    var recordingStartedAt: Date?
    var previewEnabledForRecording = false
    var levelHistory: [Float] = [0.1, 0.2]
    var lastRecordingDuration: TimeInterval = 7.4
    var previewIssue: String?
    var previewText = ""
}

// Preview material is outside this fixture; the actual capsule and its layout
// are compiled in full from IndicatorPanel.swift, without substituting its views.
struct NeumorphicSurface<S: Shape>: View {
    let shape: S
    let depth: CGFloat
    var body: some View { shape.fill(Color.gray) }
}

@main struct HUDVisibilityCheck {
    @MainActor static func main() {
        _ = NSApplication.shared
        Task { @MainActor in
            do { try await verify(); exit(0) }
            catch { fatalError("HUD verification failed: \(error)") }
        }
        NSApp.run()
    }

    @MainActor static func verify() async throws {
        var style: HUDStyle = .mini
        var timer = HUDTimerOptions()
        var reduceMotion = false
        let pipeline = DictationPipeline()
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let controller = IndicatorPanelController(pipeline: pipeline, style: { style },
            timer: { timer },
            messagePasteboard: pasteboard, reduceMotion: { reduceMotion })
        func update(_ state: PipelineState) {
            pipeline.state = state
            controller.update(for: state)
        }
        func visible() -> Bool { NSApp.windows.contains { $0 is NSPanel && $0.isVisible } }
        update(.recording)
        precondition(visible(), "Mini HUD must be visible")
        style = .none
        update(.recording)
        precondition(!visible(), "None must hide the active recording HUD immediately")
        style = .cube
        update(.recording)
        precondition(visible(), "Cube must show after None")
        style = .none
        update(.notice("Fixture notice"))
        precondition(!visible(), "None must also hide a pending notice HUD")
        print("PASS: real NSPanel Mini to None to Cube to None visibility")

        for activeStyle in [HUDStyle.mini, .cube, .sonic] {
            style = activeStyle
            timer.isEnabled = false
            pipeline.recordingStartedAt = Date().addingTimeInterval(-7)
            update(.recording)
            let panel = NSApp.windows.first { $0 is NSPanel && $0.isVisible }!
            try await Task.sleep(for: .milliseconds(60))
            let compactWidth = panel.frame.width
            pipeline.recordingStartedAt = Date().addingTimeInterval(-600)
            try await Task.sleep(for: .milliseconds(160))
            precondition(panel.frame.width == compactWidth, "Hidden time must never reserve or grow space")
            var enabledWidth: CGFloat?
            for position in HUDTimerOptions.Position.allCases {
                timer = HUDTimerOptions(isEnabled: true, position: position)
                controller.update(for: .recording, isStateChange: false)
                try await Task.sleep(for: .milliseconds(80))
                precondition(panel.frame.width > compactWidth, "Enabling the timer must expand the capsule")
                if let enabledWidth { precondition(abs(panel.frame.width - enabledWidth) < 0.5) }
                enabledWidth = panel.frame.width
            }
            timer.isEnabled = false
            controller.update(for: .recording, isStateChange: false)
            precondition(abs(panel.frame.width - compactWidth) < 0.5, "Disabling must reclaim the timer's space")
        }
        print("PASS: all three live presets default timerless and resize correctly with either timer position")

        for activeStyle in [HUDStyle.mini, .cube, .sonic] {
            style = activeStyle
            update(.recording)
            let active = NSApp.windows.first { $0 is NSPanel && $0.isVisible }!
            let timerWidth = active.frame.width
            update(.transcribing)
            let transcribingWidth = active.frame.width
            precondition(transcribingWidth > timerWidth, "The panel must grow for the longer current label")
            update(.refining)
            precondition(active.frame.width < transcribingWidth, "The panel must shrink again for Refining")
            update(.inserting)
            let panel = NSApp.windows.first { $0 is NSPanel && $0.isVisible }!
            let start = ContinuousClock.now
            let live = panel.contentView as! NSHostingView<RecordingHUDView>
            let phase = live.rootView.spatialAnimation.motion.phase
            let energy = live.rootView.spatialAnimation.motion.energy
            controller.deliveryCompleted()
            let frozen = panel.contentView as! NSHostingView<RecordingHUDView>
            precondition(frozen.rootView.snapshot?.visualizerTime == phase &&
                         frozen.rootView.snapshot?.visualizerEnergy == energy,
                         "Delivery must freeze the exact visualizer phase and energy")
            precondition(frozen.rootView.snapshot?.state == .inserting,
                         "Completion must preserve Inserting instead of the old timer")
            try await Task.sleep(for: .milliseconds(150))
            precondition(panel.isVisible && panel.alphaValue > 0 && panel.alphaValue < 1,
                         "Completion must fade immediately, not wait then disappear")
            update(.idle)
            controller.deliveryCompleted()
            precondition(frozen.rootView.snapshot?.state == .inserting,
                         "Idle must not replace the frozen final display")
            while panel.isVisible && start.duration(to: .now) < .milliseconds(650) {
                try await Task.sleep(for: .milliseconds(10))
            }
            precondition(!panel.isVisible && start.duration(to: .now) < .milliseconds(650),
                         "HUD must disappear within the 0.5-second fade plus scheduling tolerance")
            print("PASS: \(activeStyle) fades from Inserting and is hidden at \(start.duration(to: .now))")
            update(.notice("Refinement fallback remains on Home"))
            precondition(!panel.isVisible, "Late success notices must not reopen the HUD")
        }

        style = .mini
        timer.isEnabled = true
        pipeline.recordingStartedAt = Date().addingTimeInterval(-7)
        update(.recording)
        update(.inserting)
        controller.deliveryCompleted()
        try await Task.sleep(for: .milliseconds(100))
        update(.recording)
        let restarted = NSApp.windows.first { $0 is NSPanel && $0.isVisible }!
        precondition((restarted.contentView as! NSHostingView<RecordingHUDView>).rootView.snapshot == nil,
                     "New recording must restore the live view")
        try await Task.sleep(for: .milliseconds(550))
        precondition(restarted.isVisible && restarted.alphaValue == 1,
                     "An interrupted fade must not hide or dim the new recording")
        let shortTimerWidth = restarted.frame.width
        let center = restarted.frame.midX
        pipeline.recordingStartedAt = Date().addingTimeInterval(-600)
        try await Task.sleep(for: .milliseconds(250))
        precondition(restarted.frame.width > shortTimerWidth && abs(restarted.frame.midX - center) < 0.5,
                     "A new minute digit must resize the live panel without clipping or shifting its center")
        print("PASS: live status widths and timer digit growth use intrinsic layout")
        timer.isEnabled = false
        update(.idle)
        try await Task.sleep(for: .milliseconds(600))
        precondition(!visible(), "Cancel or empty speech must also dismiss the capsule")

        for activeStyle in [HUDStyle.mini, .cube, .sonic] {
            style = activeStyle
            update(.recording)
            update(.inserting)
            let confirmation = PipelineState.notice("Copied to clipboard", requiresAttention: false)
            update(confirmation)
            let panel = NSApp.windows.first { $0 is NSPanel && $0.isVisible }!
            let shown = ContinuousClock.now
            try await Task.sleep(for: .seconds(3))
            update(.idle)
            precondition(panel.isVisible && panel.alphaValue == 1,
                         "Pipeline idle must not shorten the five-second message lifetime")
            try await Task.sleep(for: .milliseconds(1700))
            // A settings observation must not restart the original deadline.
            update(.idle)
            precondition(panel.isVisible && panel.alphaValue == 1,
                         "Messages must stay fully visible before five seconds")
            while shown.duration(to: .now) < .milliseconds(5150) {
                try await Task.sleep(for: .milliseconds(10))
            }
            let frozen = panel.contentView as! NSHostingView<RecordingHUDView>
            precondition(frozen.rootView.snapshot?.state == confirmation,
                         "Dismissal must preserve the confirmation instead of restoring the timer")
            precondition(panel.isVisible && panel.alphaValue > 0 && panel.alphaValue < 1,
                         "Clipboard confirmation must start fading at five seconds")
            try await Task.sleep(for: .milliseconds(450))
            precondition(!panel.isVisible, "Copied to clipboard must disappear after the notice timeout")
            update(.idle)
            precondition(!panel.isVisible, "Later idle updates must not reopen the confirmation")
            print("PASS: \(activeStyle) clipboard confirmation fades and stays hidden")
        }

        let message = "Transcription failed: the server returned HTTP 429.\n" +
            "The selected speech model has reached its request limit. Please retry after 30 seconds.\n" +
            "Request ID: fixture-request-完整錯誤訊息-END"
        func clickCopy(_ host: NSView, in panel: NSWindow) {
            let point = NSPoint(x: host.bounds.maxX - 28, y: host.isFlipped ? 28 : host.bounds.maxY - 28)
            let location = host.convert(point, to: nil)
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            let up = NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime + 0.01, windowNumber: panel.windowNumber,
                context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!
            // Events stay inside this fixture application's queue and window.
            // No Accessibility grant or global synthetic input is involved.
            NSApp.postEvent(up, atStart: false)
            panel.sendEvent(down)
        }
        func saveRender(_ view: NSView, name: String) {
            view.layoutSubtreeIfNeeded()
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let path = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
                .appendingPathComponent(name + ".png")
            try! bitmap.representation(using: .png, properties: [:])!.write(to: path)
        }
        // The last failure's start: its five-second deadline and fade count from here,
        // not from the end of the checks below, whose duration varies by machine.
        var failedAt = Date()
        for activeStyle in [HUDStyle.mini, .cube, .sonic] {
            style = activeStyle
            update(.recording)
            let panel = NSApp.windows.first { $0 is NSPanel && $0.isVisible }!
            precondition(panel.ignoresMouseEvents, "Recording must stay click-through")
            let compact = panel.frame
            update(.failed(message))
            failedAt = Date()
            let host = panel.contentView as! NSHostingView<RecordingHUDView>
            let expanded = NSHostingView(rootView: host.rootView).fittingSize
            try await Task.sleep(for: .milliseconds(60))
            precondition(panel.frame.width > compact.width && panel.frame.width < expanded.width - 0.5,
                         "An error must visibly expand through intermediate native panel frames")
            try await Task.sleep(for: .milliseconds(300))
            precondition(abs(panel.frame.width - expanded.width) < 0.5 && panel.frame.height > 80,
                         "The error must finish expanding to fit all diagnostic lines")
            precondition(abs(panel.frame.midX - compact.midX) <= 0.5 && abs(panel.frame.minY - compact.minY) < 0.5,
                         "Expansion must keep the capsule centered and anchored above the screen edge: \(compact) to \(panel.frame)")
            precondition(!panel.ignoresMouseEvents && !panel.canBecomeKey && !panel.canBecomeMain,
                         "Messages must accept Copy without stealing destination focus")
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                host.appearance = NSAppearance(named: appearance)
                saveRender(host, name: "error-\(activeStyle.rawValue)-\(appearance.rawValue)")
            }
            clickCopy(host, in: panel)
            try await Task.sleep(for: .milliseconds(50))
            precondition(pasteboard.string(forType: .string) == message,
                         "Copy must preserve the entire message, newlines and Unicode")
            update(.idle)
            precondition(host.rootView.snapshot?.state == .failed(message) && panel.isVisible,
                         "The pipeline's idle reset must not erase the visible diagnostic")
            print("PASS: \(activeStyle) animated expansion, full multiline message and real Copy button")
        }
        func sleep(untilSecondsAfterFailure seconds: Double) async throws {
            let remaining = seconds - Date().timeIntervalSince(failedAt)
            if remaining > 0 { try await Task.sleep(for: .seconds(remaining)) }
        }
        try await sleep(untilSecondsAfterFailure: 4.5)
        precondition(visible(), "A diagnostic must remain readable beyond the old three-second timeout")
        // Five seconds, the 0.5-second fade, then a margin for the fade's completion handler.
        try await sleep(untilSecondsAfterFailure: 5.9)
        precondition(!visible(), "Failures must disappear after five seconds plus the fade")
        update(.idle)
        precondition(!visible(), "Idle must not reopen an expired failure")

        style = .mini
        update(.recording)
        update(.notice(message))
        try await Task.sleep(for: .milliseconds(350))
        update(.idle)
        try await Task.sleep(for: .milliseconds(600))
        precondition(visible(), "Recovery notices must remain readable after idle")
        try await Task.sleep(for: .milliseconds(4700))
        precondition(!visible(), "Recovery notices must also expire after five seconds plus the fade")
        update(.recording)
        update(.notice("Copied to clipboard", requiresAttention: false))
        update(.idle)
        try await Task.sleep(for: .milliseconds(60))
        update(.recording)
        let resumed = NSApp.windows.first { $0 is NSPanel && $0.isVisible }!
        let resumedFrame = resumed.frame
        try await Task.sleep(for: .milliseconds(350))
        precondition(resumed.ignoresMouseEvents && resumed.frame == resumedFrame &&
                     (resumed.contentView as! NSHostingView<RecordingHUDView>).rootView.snapshot == nil,
                     "New recording must interrupt expansion and restore a compact click-through HUD")
        reduceMotion = true
        update(.failed(message))
        let reducedHost = resumed.contentView as! NSHostingView<RecordingHUDView>
        let reducedSize = NSHostingView(rootView: reducedHost.rootView).fittingSize
        precondition(abs(resumed.frame.width - reducedSize.width) < 0.5,
                     "Reduce Motion must present the complete diagnostic without spatial animation")
        print("PASS: five-second diagnostics, notice interruption and Reduce Motion")

        try await Task.sleep(for: .seconds(4))
        controller.update(for: pipeline.state, isStateChange: false)
        update(.failed(message))
        try await Task.sleep(for: .milliseconds(1700))
        precondition(visible(), "A repeated failure must receive its own full message lifetime")
        update(.recording)
        try await Task.sleep(for: .seconds(4))
        precondition(visible(), "A cancelled message timeout must not hide a new recording")
        for activeStyle in [HUDStyle.mini, .cube, .sonic] {
            style = activeStyle
            update(.recording)
            let panel = NSApp.windows.first { $0 is NSPanel && $0.isVisible }!
            let recordingWidth = panel.frame.width
            update(.preparingModel)
            precondition(panel.ignoresMouseEvents && (activeStyle != .mini || panel.frame.width > recordingWidth),
                         "All HUD styles must show the loading label without taking focus")
            saveRender(panel.contentView!, name: "loading-\(activeStyle.rawValue)")
        }
        print("PASS: replacement deadlines, new recording cancellation and loading in all visible HUD styles")

        for (name, diagnostic, width, height) in [
            ("cjk", "聽寫失敗：無法連線至伺服器。請檢查網路後重試。\n完整原因：連線逾時，沒有收到辨識結果。", 560.0, 420.0),
            ("unbroken", String(repeating: "request_id_", count: 30) + "END", 320.0, 420.0),
            ("scrollable", String(repeating: message + "\n", count: 12), 320.0, 180.0)
        ] {
            let host = NSHostingView(rootView: IndicatorView(snapshot:
                HUDSnapshot(state: .failed(diagnostic), levels: [], elapsed: 0),
                messageMaxWidth: width, messageMaxHeight: height, messagePasteboard: pasteboard))
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            precondition(host.frame.width <= width && host.frame.height <= height + 1,
                         "Even long unbroken or multiline diagnostics must fit the available screen")
            saveRender(host, name: name)
            precondition(HUDMessageView.copy(diagnostic, to: pasteboard) && pasteboard.string(forType: .string) == diagnostic,
                         "Scrollable diagnostics must copy all text, including offscreen lines")
        }
        print("PASS: CJK, unbroken diagnostics and bounded scrollable text with complete copying")
        update(.failed("Fixture failure"))
        precondition(visible(), "A new recording failure must remain visible")
        update(.idle)
        style = .none
        update(.idle)
        precondition(!visible(), "None must hide a persistent diagnostic even after the pipeline resets to idle")
        print("PASS: repeated completion, late notices, interrupted fade, cancellation and failure visibility")
    }
}
'''


def run_suite(directory: Path, name: str, sources: dict[str, str], fixture: str) -> None:
    suite = directory / name
    suite.mkdir(parents=True, exist_ok=True)
    paths = []
    for filename, content in {**sources, "Fixture.swift": fixture}.items():
        path = suite / filename
        path.write_text(content)
        paths.append(str(path))
    binary = suite / name
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", *paths, "-o", str(binary)],
                   check=True, cwd=REPO, timeout=60)
    result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=60)
    (suite / "result.txt").write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(f"{name} failed with exit {result.returncode}:\n{result.stdout}{result.stderr}")
    print(result.stdout.strip(), flush=True)


def verify(directory: Path, skip_hud: bool) -> None:
    run_suite(directory, "hotkey-suspension", {
        "HotkeyService.swift": source("Sources/App/Hotkeys/HotkeyService.swift"),
        "CarbonHotkey.swift": source("Sources/App/Hotkeys/CarbonHotkey.swift"),
        "EventTapHotkey.swift": source("Sources/App/Hotkeys/EventTapHotkey.swift"),
        "Hotkey.swift": source("Packages/AirdraftCore/Sources/AirdraftCore/Settings/Hotkey.swift"),
        "HotkeyPressState.swift": source("Packages/AirdraftCore/Sources/AirdraftCore/Settings/HotkeyPressState.swift"),
        "HotkeyTriggerState.swift": source("Packages/AirdraftCore/Sources/AirdraftCore/Settings/HotkeyTriggerState.swift"),
    }, HOTKEY_FIXTURE)
    run_suite(directory, "microphone-selection", {
        "MicrophoneStore.swift": source("Sources/App/App/MicrophoneStore.swift"),
        "Microphone.swift": source("Packages/AirdraftCore/Sources/AirdraftCore/Audio/Microphone.swift"),
    }, MICROPHONE_FIXTURE)
    if skip_hud:
        print("SKIP: HUD visibility, --skip-hud selected", flush=True)
    else:
        run_suite(directory, "hud-visibility", {
            "IndicatorPanel.swift": source("Sources/App/HUD/IndicatorPanel.swift"),
            "SpatialHUDVisualizer.swift": source("Sources/App/HUD/SpatialHUDVisualizer.swift"),
            "HUDTimerOptions.swift": source("Packages/AirdraftCore/Sources/AirdraftCore/Settings/HUDTimerOptions.swift"),
            "PipelineState.swift": "import Foundation\npublic enum PipelineState" + source(
                "Packages/AirdraftCore/Sources/AirdraftCore/Pipeline/DictationPipeline.swift"
            ).split("public enum PipelineState", 1)[1].split("public struct DictationOutcome", 1)[0],
        }, HUD_FIXTURE)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-hud", action="store_true", help="Avoid showing the isolated HUD test panel")
    parser.add_argument("--output", type=Path, help="Keep compiled harnesses and results in this directory")
    args = parser.parse_args()
    if args.output:
        verify(args.output.resolve(), args.skip_hud)
    else:
        with tempfile.TemporaryDirectory(prefix="airdraft-native-behaviors-") as temporary:
            verify(Path(temporary), args.skip_hud)


if __name__ == "__main__":
    main()
