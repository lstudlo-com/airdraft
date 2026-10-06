#!/usr/bin/env python3
"""Exercise production sliders in an isolated native window, without app data or audio.

Keyboard and pointer events target only the fixture's own NSWindow. No system input,
settings, provider APIs, credentials, microphone or playback are used.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import subprocess
import tempfile


REPO = Path(__file__).resolve().parents[1]

FIXTURE = r'''
import AppKit
import Observation
import SwiftUI

@MainActor @Observable final class SliderValues {
    var temperature = 0.5
    var playback = RecordingPlayback()
    var disabled = 0.5
    var native = 0.5
}

// The production History view needs only these clock/seek members. This fixture
// has no audio player or playback capability.
@MainActor @Observable final class RecordingPlayback {
    var currentTime = 12.3
    let duration = 20.0
    var seekCount = 0
    func seek(to value: Double) { seekCount += 1; currentTime = value }
}

struct Sliders: View {
    @Bindable var values: SliderValues
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Temperature")
            SoftSlider(title: "Temperature", value: $values.temperature, range: 0...1, step: 0.1)
                .accessibilityIdentifier("temperature")
            Text("Playback position · five-second keys")
            HStack { HistoryPlaybackProgress(playback: values.playback) }
            SoftSlider(title: "Disabled", value: $values.disabled, range: 0...1, step: 0.1)
                .disabled(true).accessibilityIdentifier("disabled")
            Slider(value: $values.native, in: 0...1, step: 0.1) { Text("Native comparison") }
                .accessibilityIdentifier("native")
        }.padding(24).frame(width: 400).background(Color(nsColor: .windowBackgroundColor))
    }
}

// Unhandled fixture input must not produce the system alert sound.
final class SilentWindow: NSWindow {
    override func noResponder(for eventSelector: Selector) {}
}

@main @MainActor struct VerifySliders {
    static func main() throws {
        setbuf(stdout, nil)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let values = SliderValues()
            let window = SilentWindow(contentRect: NSRect(x: 240, y: 200, width: 448, height: 320),
                                      styleMask: [.titled], backing: .buffered, defer: false)
            window.title = "Silent native slider verification"
            window.appearance = NSAppearance(named: appearance)
            window.contentView = NSHostingView(rootView: Sliders(values: values))
            window.makeKeyAndOrderFront(nil)
            pump()
            let temperature = find("temperature", in: window)
            let playback = find("playback", in: window)
            let disabled = find("disabled", in: window)
            focus(temperature)
            pump()
            precondition(isFocused(temperature), "Production slider must accept focus")
            arrow(.right, window: window)
            equal(values.temperature, 0.6, "One arrow must change temperature once")
            arrow(.left, window: window)
            equal(values.temperature, 0.5, "Left arrow must reverse one step")
            precondition(action(temperature, "accessibilityPerformIncrement"))
            pump()
            equal(values.temperature, 0.6, "Accessibility increment must stay available")
            precondition(action(temperature, "accessibilityPerformDecrement"))
            pump()
            equal(values.temperature, 0.5, "Accessibility decrement must stay available")
            values.temperature = 1
            pump()
            arrow(.right, window: window)
            equal(values.temperature, 1, "Upper bound")
            values.temperature = 0
            pump()
            arrow(.left, window: window)
            equal(values.temperature, 0, "Lower bound")

            // Native focus traversal is exercised without changing global keyboard preferences.
            focus(temperature)
            window.selectNextKeyView(nil)
            pump()
            precondition(isFocused(playback), "Next key view must reach the next production slider")
            let seeks = values.playback.seekCount
            arrow(.right, window: window)
            equal(values.playback.currentTime, 17.3, "History uses a five-second keyboard increment")
            precondition(values.playback.seekCount == seeks + 1, "One arrow must invoke the actual History seek binding once")
            arrow(.right, window: window)
            equal(values.playback.currentTime, 20, "History clamps at duration")
            arrow(.left, window: window)
            equal(values.playback.currentTime, 15, "History moves once, without a duplicate consumer handler")
            precondition(action(playback, "accessibilityPerformIncrement"))
            pump()
            equal(values.playback.currentTime, 15.1, "Accessibility keeps the fine adjustment step")
            window.selectNextKeyView(nil)
            pump()
            precondition(isFocused(find("native", in: window)), "Disabled slider must be skipped in native focus traversal")
            precondition(!action(disabled, "accessibilityPerformIncrement"))
            equal(values.disabled, 0.5, "Disabled accessibility adjustment must not mutate value")

            drag(temperature, from: 0.3, to: 0.8, window: window)
            precondition(values.temperature >= 0.7 && values.temperature <= 0.9,
                         "Pointer drag must update the actual slider: \(values.temperature)")
            drag(disabled, from: 0.3, to: 0.8, window: window)
            equal(values.disabled, 0.5, "Disabled pointer drag must not mutate value")
            focus(temperature)
            pump()
            try capture(window, to: directory.appendingPathComponent("slider-focus-\(name).png"))
            window.orderOut(nil)
            window.contentView = nil
            print("NATIVE_UI_CONTROLS_PASS \(name) focus one-step bounds history-step AX disabled pointer native-next-key-view")
        }
    }

    static func equal(_ actual: Double, _ expected: Double, _ message: String) {
        precondition(abs(actual - expected) < 0.00001, "\(message): \(actual), expected \(expected)")
    }
    static func value(_ object: NSObject, _ key: String) -> Any? {
        object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
    }
    static func descendants(_ object: Any) -> [NSObject] {
        guard let item = object as? NSObject else { return [] }
        return [item] + ((value(item, "accessibilityChildren") as? [Any]) ?? []).flatMap(descendants)
    }
    static func find(_ id: String, in window: NSWindow) -> NSObject {
        guard let item = descendants(window).first(where: {
            value($0, "accessibilityIdentifier") as? String == id ||
                (id == "playback" && value($0, "accessibilityLabel") as? String == "Playback position")
        }) else {
            preconditionFailure("Missing production control: \(id)")
        }
        return item
    }
    static func focus(_ object: NSObject) {
        let selector = NSSelectorFromString("setAccessibilityFocused:")
        precondition(object.responds(to: selector))
        let call = unsafeBitCast(object.method(for: selector), to: (@convention(c) (NSObject, Selector, Bool) -> Void).self)
        call(object, selector, true)
    }
    static func isFocused(_ object: NSObject) -> Bool { value(object, "isAccessibilityFocused") as? Bool == true }
    static func action(_ object: NSObject, _ name: String) -> Bool {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return false }
        let call = unsafeBitCast(object.method(for: selector), to: (@convention(c) (NSObject, Selector) -> Bool).self)
        return call(object, selector)
    }
    static func arrow(_ direction: MoveCommandDirection, window: NSWindow) {
        let scalar = direction == .right ? NSRightArrowFunctionKey : NSLeftArrowFunctionKey
        let characters = String(UnicodeScalar(scalar)!)
        window.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: direction == .right ? 124 : 123)!)
        pump()
    }
    static func drag(_ object: NSObject, from: CGFloat, to: CGFloat, window: NSWindow) {
        guard let frame = (value(object, "accessibilityFrame") as? NSValue)?.rectValue else {
            preconditionFailure("Control needs an accessibility frame")
        }
        for (type, fraction) in [(NSEvent.EventType.leftMouseDown, from), (.leftMouseDragged, to), (.leftMouseUp, to)] {
            let point = window.convertPoint(fromScreen: NSPoint(x: frame.minX + frame.width * fraction, y: frame.midY))
            let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
            // Gesture recognizers read NSApp.currentEvent. Use this process's
            // event queue, never CGEvent posting or another application's input.
            NSApp.postEvent(event, atStart: false)
            while let queued = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.02), inMode: .default, dequeue: true) {
                NSApp.sendEvent(queued)
            }
            pump()
        }
    }
    static func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.12)) }
    static func capture(_ window: NSWindow, to path: URL) throws {
        let view = window.contentView!
        view.layoutSubtreeIfNeeded()
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: path)
    }
}
'''


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="airdraft-ui-controls-") as temporary:
        directory = Path(temporary)
        fixture = directory / "Fixture.swift"
        history = (REPO / "Sources/App/Views/HistoryRecordingControls.swift").read_text()
        progress = "private struct HistoryPlaybackProgress:" + history.split("private struct HistoryPlaybackProgress:", 1)[1]
        formatter = re.search(r"    static func time\(_ seconds: Double\) -> String \{.*?\n    \}", history, re.S).group(0)
        fixture.write_text(FIXTURE + "\nenum HistoryRecordingControls {\n" + formatter + "\n}\n" + progress)
        # Compile the production motion definition, without sidebar-only dependencies.
        motion = directory / "SelectionMotion.swift"
        navigation = (REPO / "Sources/App/Views/NavigationStyle.swift").read_text()
        motion.write_text(navigation.split("enum NavigationStyle {", 1)[0])
        binary = directory / "verify-controls"
        subprocess.run([
            "swiftc", "-parse-as-library",
            str(REPO / "Sources/App/Views/SoftControls.swift"),
            str(REPO / "Sources/App/Views/SurfaceShadows.swift"),
            str(motion), str(fixture), "-o", str(binary),
        ], check=True)
        subprocess.run([str(binary), str(args.output.resolve())], check=True)


if __name__ == "__main__":
    main()
