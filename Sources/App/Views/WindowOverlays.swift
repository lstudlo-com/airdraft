import AppKit
import AVFoundation
import AirdraftCore
import SwiftUI

enum WindowOverlay: Hashable {
    case microphone
    case account
}

struct MicrophoneSelectionOverlay: View {
    /// Wide enough for common device names (up to about 175 pt) beside the ten-cell meter.
    static let width: CGFloat = 336

    @Environment(AppContainer.self) private var container
    @State private var previews: MicrophoneLevelPreviews
    @State private var isVisible = false
    let onClose: () -> Void
    var renderLevel: Float? = nil

    @MainActor init(onClose: @escaping () -> Void, renderLevel: Float? = nil,
                    previews: MicrophoneLevelPreviews? = nil) {
        self.onClose = onClose
        self.renderLevel = renderLevel
        self._previews = State(initialValue: previews ?? MicrophoneLevelPreviews())
    }

    private var preference: MicrophonePreference { container.settings.microphone }
    private var selected: Microphone? { container.microphones.selected(preference) }
    private var isBusy: Bool { container.pipeline.isBusy }
    private var systemDefault: Microphone? {
        container.microphones.devices.first { $0.id == container.microphones.systemDefaultID }
    }
    private static let rowSpacing: CGFloat = 2
    /// Row inset, checkmark column and its gap: where a device name starts.
    private static let nameInset = Theme.overlayRowInset + 12 + 8
    /// Six rows fit before the list scrolls; each row is as tall as a sidebar destination.
    private static let listHeightCap = 6 * NavigationStyle.rowHeight + 5 * rowSpacing

    private enum Note { case busy, allowAccess, openSettings, restricted }

    /// Live state, or a fixed one while rendering so every note can be inspected.
    private var note: Note? {
        if let forced = RenderMode.value("MIC_NOTE") {
            return ["busy": .busy, "allow": .allowAccess, "denied": .openSettings, "restricted": .restricted][forced]
        }
        guard renderLevel == nil else { return nil }
        if isBusy { return .busy }
        switch container.permissions.microphone {
        case .notDetermined: return .allowAccess
        case .denied: return .openSettings
        case .restricted: return .restricted
        default: return nil
        }
    }

    var body: some View {
        OverlayPanel(title: "Microphone", width: Self.width, onClose: onClose) {
            ScrollView {
                VStack(spacing: Self.rowSpacing) {
                    choice(title: "System Default", device: systemDefault, selected: preference.uid == nil) {
                        choose(.systemDefault)
                    }
                    ForEach(container.microphones.devices) { device in
                        choice(title: device.name, device: device, selected: preference.uid == device.uid) {
                            choose(MicrophonePreference(uid: device.uid, name: device.name))
                        }
                    }
                    if preference.uid != nil && selected == nil {
                        choice(title: preference.name, device: nil, selected: true) {}
                    }
                }
            }
            .frame(maxHeight: Self.listHeightCap)
            .fixedSize(horizontal: false, vertical: true)

            if let note {
                Group {
                    switch note {
                    case .busy:
                        EmptyNote("Finish the current operation to change microphones.")
                    case .allowAccess:
                        Button("Allow Microphone Access…") {
                            Task {
                                await container.permissions.requestMicrophone()
                                synchronizePreviews()
                            }
                        }
                        .buttonStyle(SoftButtonStyle())
                    case .openSettings:
                        Button("Open Microphone Settings…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                        }
                        .buttonStyle(SoftButtonStyle())
                    case .restricted:
                        EmptyNote("Microphone access is restricted by this Mac's settings.")
                    }
                }
                .padding(.horizontal, Theme.overlayRowInset)
                .padding(.top, 6)
                .padding(.bottom, 2)
            }
        }
        .onAppear {
            isVisible = true
            container.microphones.refresh()
            container.permissions.refresh()
            synchronizePreviews()
        }
        .onDisappear {
            isVisible = false
            previews.stop()
        }
        .onChange(of: isBusy) { _, _ in synchronizePreviews() }
        .onChange(of: container.permissions.microphone) { _, _ in synchronizePreviews() }
        .onChange(of: preference) { _, _ in synchronizePreviews() }
        .onChange(of: container.microphones.devices) { _, _ in synchronizePreviews() }
        .onChange(of: container.microphones.systemDefaultID) { _, _ in synchronizePreviews() }
    }

    private func choose(_ newPreference: MicrophonePreference) {
        guard !isBusy else { return }
        container.settings.microphone = container.microphones.selection(newPreference, preservingChannelFrom: preference)
    }

    private func synchronizePreviews() {
        guard isVisible, renderLevel == nil, !isBusy,
              container.permissions.microphone == .authorized else {
            previews.stop()
            return
        }
        previews.synchronize(devices: container.microphones.devices, selection: preference,
                             systemDefaultID: container.microphones.systemDefaultID)
    }

    private func choice(title: String, device: Microphone?, selected: Bool,
                        action: @escaping () -> Void) -> some View {
        let error = device.flatMap { previews.errors[$0.uid] }
        let level = device.map { renderLevel ?? previews.levels[$0.uid] ?? 0 } ?? 0
        return VStack(alignment: .leading, spacing: 2) {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .opacity(selected ? 1 : 0)
                        .frame(width: 12)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    MicrophoneLevelMeter(level: level)
                        .opacity(device == nil || error != nil ? 0.4 : 1)
                }
                .padding(.horizontal, Theme.overlayRowInset)
                .frame(height: NavigationStyle.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(NavigationRowStyle(selected: selected))
            .disabled(device == nil || isBusy)
            .help(device == nil ? "\(title) is unavailable. Reconnect it or choose another microphone." : title)
            .accessibilityLabel(title)
            .accessibilityValue(device == nil ? "Unavailable" : "Input level \(MicrophoneLevelMeter.steps(for: level)) of 10")
            .accessibilityAddTraits(selected ? .isSelected : [])

            if let error {
                EmptyNote(error).padding(.leading, Self.nameInset).padding(.trailing, Theme.overlayRowInset)
            } else if device == nil {
                EmptyNote("Unavailable").padding(.leading, Self.nameInset).padding(.trailing, Theme.overlayRowInset)
            }
        }
    }
}

struct MicrophoneLevelMeter: View {
    let level: Float

    static func steps(for level: Float) -> Int {
        guard level.isFinite else { return 0 }
        return Int((min(1, max(0, level)) * 10).rounded(.up))
    }

    /// Ten cells in a 22 pt well, which leaves a 5 pt margin inside a 32 pt row.
    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(1...10, id: \.self) { step in
                Capsule()
                    .fill(LinearGradient(
                        colors: step <= Self.steps(for: level)
                            ? [Color.primary.opacity(0.85), Color.primary.opacity(0.6)]
                            : [Color.primary.opacity(0.10), Color.primary.opacity(0.06)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay {
                        Capsule().strokeBorder(.white.opacity(step <= Self.steps(for: level) ? 0.18 : 0), lineWidth: 0.5)
                    }
                    .frame(width: 5, height: 12)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background { NeumorphicSurface(shape: Capsule(), inset: true, depth: 1.5) }
        .fixedSize()
        .accessibilityHidden(true)
    }
}

// Retains the shared overlay entry used by Debug previews without fake billing data.
struct AccountOverlay: View {
    let onClose: () -> Void
    var body: some View { LicenseView(onClose: onClose) }
}
