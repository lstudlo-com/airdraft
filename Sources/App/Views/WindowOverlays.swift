import AppKit
import AVFoundation
import AirdraftCore
import SwiftUI

enum WindowOverlay: Hashable {
    case microphone
    case account
}

struct MicrophoneSelectionOverlay: View {
    @Environment(AppContainer.self) private var container
    @State private var previews = MicrophoneLevelPreviews()
    @State private var isVisible = false
    let onClose: () -> Void
    var renderLevel: Float? = nil

    private var preference: MicrophonePreference { container.settings.microphone }
    private var selected: Microphone? { container.microphones.selected(preference) }
    private var isBusy: Bool { container.pipeline.state.isBusy }
    private var systemDefault: Microphone? {
        container.microphones.devices.first { $0.id == container.microphones.systemDefaultID }
    }
    private var choiceCount: Int {
        container.microphones.devices.count + 1 + (preference.uid != nil && selected == nil ? 1 : 0)
    }

    var body: some View {
        OverlayPanel(title: "Microphone", width: 400, onClose: onClose) {
            ScrollView {
                VStack(spacing: 2) {
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
            .frame(maxHeight: min(CGFloat(choiceCount) * 40 + CGFloat(choiceCount - 1) * 2, 250))
            .fixedSize(horizontal: false, vertical: true)

            if renderLevel == nil {
                if isBusy {
                    EmptyNote("Finish dictation to change microphones.")
                } else if container.permissions.microphone == .notDetermined {
                    Button("Allow Microphone Access…") {
                        Task {
                            await container.permissions.requestMicrophone()
                            synchronizePreviews()
                        }
                    }
                    .buttonStyle(SoftButtonStyle())
                } else if container.permissions.microphone == .denied {
                    Button("Open Microphone Settings…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                    }
                    .buttonStyle(SoftButtonStyle())
                } else if container.permissions.microphone == .restricted {
                    EmptyNote("Microphone access is restricted by this Mac's settings.")
                }
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
        var next = newPreference
        if let selected, container.microphones.selected(next)?.uid == selected.uid {
            next.channelIndex = preference.channelIndex
        }
        container.settings.microphone = next
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
        return VStack(alignment: .leading, spacing: 4) {
            Button(action: action) {
                HStack(spacing: Theme.controlSpacing) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .opacity(selected ? 1 : 0)
                        .frame(width: 12)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Spacer(minLength: Theme.controlSpacing)
                    MicrophoneLevelMeter(level: level)
                        .opacity(device == nil || error != nil ? 0.4 : 1)
                }
                .padding(.horizontal, Theme.sectionTitleSpacing)
                .frame(height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(NavigationRowStyle(selected: selected))
            .disabled(device == nil || isBusy)
            .help(device == nil ? "\(title) is unavailable. Reconnect it or choose another microphone." : title)
            .accessibilityLabel(title)
            .accessibilityValue(device == nil ? "Unavailable" : "Input level \(MicrophoneLevelMeter.steps(for: level)) of 10")
            .accessibilityAddTraits(selected ? .isSelected : [])

            if let error {
                EmptyNote(error)
                    .padding(.horizontal, Theme.sectionTitleSpacing)
            } else if device == nil {
                EmptyNote("Unavailable")
                    .padding(.horizontal, Theme.sectionTitleSpacing)
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

    var body: some View {
        HStack(spacing: 3) {
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
                    .frame(width: 6, height: 14)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background { NeumorphicSurface(shape: Capsule(), inset: true, depth: 1.8) }
        .fixedSize()
        .accessibilityHidden(true)
    }
}

// Account prototypes are excluded from production.
#if DEBUG
/// Account and subscription. Sample data until account services exist.
struct AccountOverlay: View {
    let onClose: () -> Void

    var body: some View {
        OverlayPanel(title: "Account", width: 448, onClose: onClose) {
            PageSection("Profile") {
                SettingsCard {
                    HStack(spacing: 12) {
                        Text("LC")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(Color.accentColor, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Light Chen")
                                .font(.system(size: 13, weight: .semibold))
                            Text(verbatim: "light@example.com")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }

            PageSection("Subscription") {
                SettingsCard {
                    SettingRow(title: "Airdraft Pro") {
                        PillTag(text: "ACTIVE")
                    }
                    RowDivider()
                    SettingRow(title: "Billing") {
                        Text("Monthly").foregroundStyle(.secondary)
                    }
                    RowDivider()
                    SettingRow(title: "Next renewal") {
                        Text("24 Oct 2026").foregroundStyle(.secondary)
                    }
                }
            }

            EmptyNote("Sample information: account and billing are not connected yet.")
        }
    }
}

#else
struct AccountOverlay: View {
    let onClose: () -> Void
    var body: some View { EmptyView() }
}
#endif
