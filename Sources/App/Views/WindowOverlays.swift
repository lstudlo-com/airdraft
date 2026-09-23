import AppKit
import AVFoundation
import AirdraftCore
import Observation
import SwiftUI

enum WindowOverlay {
    case microphone
    case settings
}

@MainActor
@Observable
private final class MicrophoneLevelPreview {
    var level: Float = 0
    var error: String?
    private let recorder = AudioRecorder()
    private var generation = 0

    func start(_ preference: MicrophonePreference) {
        stop()
        generation += 1
        let current = generation
        error = nil
        recorder.levelHandler = { [weak self] level in
            Task { @MainActor [weak self] in
                guard let self, self.generation == current else { return }
                self.level = level
            }
        }
        recorder.interruptionHandler = { [weak self] reason in
            Task { @MainActor [weak self] in
                guard let self, self.generation == current else { return }
                self.stop()
                self.error = reason.localizedDescription
            }
        }
        do {
            try recorder.startLevelMonitoring(microphone: preference)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func stop() {
        generation += 1
        if recorder.isRecording { recorder.cancel() }
        level = 0
    }
}

struct MicrophoneSelectionOverlay: View {
    @Environment(AppContainer.self) private var container
    @State private var preview = MicrophoneLevelPreview()
    let onClose: () -> Void
    var renderLevel: Float? = nil

    private var preference: MicrophonePreference { container.settings.microphone }
    private var selected: Microphone? { container.microphones.selected(preference) }
    private var isBusy: Bool { container.pipeline.state.isBusy }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Microphone")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Choose the input used for dictation")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close microphone choices")
            }
            .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Image(systemName: "waveform")
                        .foregroundStyle(.secondary)
                    Text("Input level")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(selected?.name ?? "No input")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.10))
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: max(0, geometry.size.width * CGFloat(renderLevel ?? preview.level)))
                            .animation(.easeOut(duration: 0.12), value: renderLevel ?? preview.level)
                    }
                }
                .frame(height: 6)
                Text(levelMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(preview.error == nil ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                if container.permissions.microphone == .notDetermined && renderLevel == nil {
                    Button("Allow microphone access…") {
                        Task {
                            await container.permissions.requestMicrophone()
                            restartPreview()
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
            }
            .padding(14)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
            .padding(.bottom, 18)

            Text("AVAILABLE INPUTS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
                .padding(.horizontal, 4)
                .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 3) {
                    choice(title: "System default", subtitle: systemDefaultSubtitle,
                           selected: preference.uid == nil) {
                        choose(.systemDefault)
                    }
                    ForEach(container.microphones.devices) { device in
                        choice(title: device.name,
                               subtitle: device.id == container.microphones.systemDefaultID ? "macOS default input" : nil,
                               selected: preference.uid == device.uid) {
                            choose(MicrophonePreference(uid: device.uid, name: device.name))
                        }
                    }
                    if let uid = preference.uid, selected == nil {
                        choice(title: preference.name, subtitle: "Unavailable · reconnect to use",
                               selected: true, enabled: false) {}
                            .id(uid)
                    }
                }
            }
            .frame(height: min(CGFloat(container.microphones.devices.count + 1 + (preference.uid != nil && selected == nil ? 1 : 0)) * 46 + 9, 204))
        }
        .padding(18)
        .frame(width: 382)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.22), radius: 24, x: 0, y: 12)
        .onAppear {
            container.microphones.refresh()
            container.permissions.refresh()
            restartPreview()
        }
        .onDisappear { preview.stop() }
        .onChange(of: isBusy) { _, _ in restartPreview() }
        .onChange(of: container.permissions.microphone) { _, _ in restartPreview() }
    }

    private var systemDefaultSubtitle: String? {
        guard let defaultID = container.microphones.systemDefaultID,
              let device = container.microphones.devices.first(where: { $0.id == defaultID }) else { return nil }
        return device.name
    }

    private var levelMessage: String {
        if let error = preview.error { return error }
        if isBusy { return "Finish dictation before changing the input." }
        if container.permissions.microphone == .denied { return "Allow microphone access in System Settings to preview input." }
        if container.permissions.microphone == .notDetermined { return "Allow access to check the input level." }
        if selected == nil { return "Reconnect this microphone or choose another input." }
        return "Speak to check this microphone. No audio is saved."
    }

    private func choose(_ newPreference: MicrophonePreference) {
        guard !isBusy else { return }
        container.settings.microphone = newPreference
        restartPreview()
    }

    private func restartPreview() {
        preview.stop()
        guard renderLevel == nil, !isBusy,
              container.permissions.microphone == .authorized,
              selected != nil else { return }
        preview.start(preference)
    }

    private func choice(title: String, subtitle: String?, selected: Bool,
                        enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: "mic")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 11)
            .frame(minHeight: subtitle == nil ? 40 : 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .background(selected ? Color.primary.opacity(0.075) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!enabled || isBusy)
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct AccountSettingsOverlay: View {
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Settings")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close settings")
            }

            PageSection("Account") {
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
                    HStack(alignment: .firstTextBaseline) {
                        Text("Airdraft Pro")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text("Active")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                    RowDivider()
                    HStack {
                        Text("Billing")
                        Spacer()
                        Text("Monthly")
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12))
                    HStack {
                        Text("Next renewal")
                        Spacer()
                        Text("24 Oct 2026")
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12))
                }
            }

            Text("Preview information — account and billing are not connected yet.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 448)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 30, x: 0, y: 14)
    }
}
