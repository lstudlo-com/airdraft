import AppKit
import AirdraftCore
import SwiftUI

/// Click "Change", press the key or combination, done. A modifier pressed and
/// released on its own becomes a modifier-only hotkey (Right ⌥, fn).
struct HotkeyRecorderView: View {
    @Environment(AppContainer.self) private var container
    @State private var recording = false
    @State private var monitors: [Any] = []
    @State private var pendingModifier: UInt16?

    var body: some View {
        HStack(spacing: 10) {
            if container.settings.hotkey != .optionSpace, !recording {
                Button { container.settings.hotkey = .optionSpace } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Reset to ⌥ Space")
            }
            if recording {
                Text("Press a key or combination…  Esc cancels")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentColor.opacity(0.12)))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.accentColor))
            } else {
                KeyCaps(hotkey: container.settings.hotkey)
            }
            Button(recording ? "Cancel" : "Record shortcut") {
                if recording { stop() } else { start() }
            }
            .buttonStyle(SoftButtonStyle())
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        pendingModifier = nil
        container.hotkeys.suspended = true

        let flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let code = event.keyCode
            guard let bit = Hotkey.modifierFlag(for: code) else { return nil }
            let down = UInt64(event.modifierFlags.rawValue) & bit != 0
            if down {
                pendingModifier = code
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
        container.settings.hotkey = hotkey
        stop()
    }

    private func stop() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors = []
        pendingModifier = nil
        recording = false
        container.hotkeys.suspended = false
    }
}
