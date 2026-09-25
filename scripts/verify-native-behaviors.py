#!/usr/bin/env python3
"""Compile and exercise native app behaviors without opening real app data.

Uses the production hotkey backends, microphone selection and HUD controller.
Core value types are compiled directly; only permissions and HUD content/pipeline
are fixtures. No models, credentials, preferences, recordings or history are read.
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
import SwiftUI

enum AppIdentity { static let logSubsystem = "com.lstudlo.airdraft.test.hud" }
enum HUDStyle { case classic, mini, none }
enum PipelineState { case idle, recording, failed, notice }

@MainActor final class DictationPipeline {
    var isRecording = true
    var previewEnabledForRecording = false
}

struct RecordingHUDView: View {
    let pipeline: DictationPipeline
    let style: HUDStyle
    let showPreview: Bool
    var body: some View { Text("Airdraft native behavior verification") }
    static func size(for style: HUDStyle, preview: Bool) -> CGSize { IndicatorView.size(for: style) }
}

struct IndicatorView {
    static func size(for style: HUDStyle) -> CGSize { CGSize(width: 172, height: 34) }
}

@main struct HUDVisibilityCheck {
    @MainActor static func main() {
        _ = NSApplication.shared
        var style: HUDStyle = .classic
        let controller = IndicatorPanelController(pipeline: DictationPipeline(), style: { style })
        func visible() -> Bool { NSApp.windows.contains { $0 is NSPanel && $0.isVisible } }
        controller.update(for: .recording)
        precondition(visible(), "Classic HUD must be visible")
        style = .none
        controller.update(for: .recording)
        precondition(!visible(), "None must hide the active recording HUD immediately")
        style = .mini
        controller.update(for: .recording)
        precondition(visible(), "Mini must show after None")
        style = .none
        controller.update(for: .notice)
        precondition(!visible(), "None must also hide a pending notice HUD")
        print("PASS: real NSPanel Classic to None to Mini to None visibility")
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
    result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)
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
    }, HOTKEY_FIXTURE)
    run_suite(directory, "microphone-selection", {
        "MicrophoneStore.swift": source("Sources/App/App/MicrophoneStore.swift"),
        "Microphone.swift": source("Packages/AirdraftCore/Sources/AirdraftCore/Audio/Microphone.swift"),
    }, MICROPHONE_FIXTURE)
    if skip_hud:
        print("SKIP: HUD visibility, --skip-hud selected", flush=True)
    else:
        hud = source("Sources/App/HUD/IndicatorPanel.swift")
        boundary = "/// Preview remains nonactivating"
        if boundary not in hud:
            raise RuntimeError("HUD controller source boundary changed; update this verifier")
        run_suite(directory, "hud-visibility", {
            "IndicatorPanelController.swift": hud.split(boundary, 1)[0],
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
