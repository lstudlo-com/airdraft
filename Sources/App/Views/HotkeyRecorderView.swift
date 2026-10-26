import AppKit
import AirdraftCore
import SwiftUI

/// Click "Change", press the key or combination, done. A modifier pressed and
/// released on its own becomes a modifier-only hotkey (Right ⌥, fn).
/// Multiple modifiers held together become a side-independent combination.
struct HotkeyRecorderView: View {
    @Environment(AppContainer.self) private var container
    /// Nil edits the dictation shortcut. Profile and Edit shortcuts (AD-104)
    /// pass their own binding; they start unset and can be cleared.
    var shortcut: Binding<Hotkey?>?
    /// The accessible name of this recorder's shortcut.
    var accessibilityName: String = String(localized: "Dictation shortcut")
    @State private var recording = false
    @State private var monitors: [Any] = []
    @State private var pendingModifier: UInt16?
    @State private var pendingModifiers: UInt64 = 0

    /// The dictation recorder keeps its visible title; extra shortcuts name theirs.
    private var buttonAccessibilityLabel: String {
        if shortcut == nil { return recording ? String(localized: "Cancel") : String(localized: "Record Shortcut") }
        return recording ? String(localized: "Cancel recording \(accessibilityName)") : String(localized: "Record \(accessibilityName)")
    }

    private var current: Hotkey? {
        shortcut.map { $0.wrappedValue } ?? container.settings.hotkey
    }

    var body: some View {
        HStack(spacing: 10) {
            if let shortcut, shortcut.wrappedValue != nil, !recording {
                Button { shortcut.wrappedValue = nil } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove Shortcut")
                .accessibilityLabel("Remove \(accessibilityName)")
            }
            if shortcut == nil, container.settings.hotkey != .controlOption, !recording {
                Button { container.settings.hotkey = .controlOption } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Reset to \(Hotkey.controlOption.localizedDisplayString)")
                .accessibilityLabel("Reset shortcut to \(Hotkey.controlOption.localizedDisplayString)")
            }
            if recording {
                Text("Press a key or combination…  Esc cancels")
                    .appFont(.detail, weight: .medium)
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(SoftControl.shape.fill(Color.accentColor.opacity(0.12)))
                    .overlay(SoftControl.shape.strokeBorder(Color.accentColor))
            } else if let current {
                KeyCaps(hotkey: current)
            } else {
                Text("Not set").appFont(.body).foregroundStyle(.secondary)
            }
            Button(recording ? "Cancel" : "Record Shortcut") {
                if recording { stop() } else { start() }
            }
            .buttonStyle(SoftButtonStyle())
            .accessibilityLabel(buttonAccessibilityLabel)
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        pendingModifier = nil
        pendingModifiers = 0
        container.hotkeys.suspended = true

        let flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let code = event.keyCode
            guard let bit = Hotkey.modifierFlag(for: code) else { return nil }
            let mods = UInt64(event.modifierFlags.rawValue) & Hotkey.relevantModifierMask
            if pendingModifiers.nonzeroBitCount > 1, mods & pendingModifiers != pendingModifiers {
                finish(Hotkey(keyCode: 0, modifiers: pendingModifiers, isModifierOnly: true))
                return nil
            }
            let down = mods & bit != 0
            if down {
                pendingModifier = code
                pendingModifiers = mods
            } else if pendingModifier == code {
                finish(Hotkey(keyCode: code, isModifierOnly: true))
            }
            return nil
        }
        let keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = UInt64(event.modifierFlags.rawValue) & Hotkey.relevantModifierMask
            if event.keyCode == 53, mods == 0 { // Esc
                stop()
                return nil
            }
            pendingModifier = nil
            finish(Hotkey(keyCode: event.keyCode, modifiers: mods, isModifierOnly: false))
            return nil
        }
        monitors = [flagsMonitor, keyMonitor].compactMap { $0 }
    }

    private func finish(_ hotkey: Hotkey) {
        if let shortcut { shortcut.wrappedValue = hotkey } else { container.settings.hotkey = hotkey }
        stop()
    }

    private func stop() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors = []
        pendingModifier = nil
        pendingModifiers = 0
        recording = false
        container.hotkeys.suspended = false
    }
}
