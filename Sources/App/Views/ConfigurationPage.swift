import AVFoundation
import AirdraftCore
import SwiftUI

struct ConfigurationPage: View {
    @Environment(AppContainer.self) private var container

    @State private var pendingRetention: AudioRetention?
    @State private var confirmRetention = false
    @State var search = SettingsSearchState()

    var body: some View {
        @Bindable var settings = container.settings
        SettingsSearchScaffold(search: search) {
            MicrophoneSettings()

            PageSection("Appearance") {
                SettingsCard {
                    SettingRow(title: "Theme") {
                        HStack(spacing: 10) {
                            ForEach(AppearanceMode.allCases) { mode in
                                ChoiceTile(title: mode.title, selected: settings.appearance == mode, action: { settings.appearance = mode }) {
                                    ThemePreview(mode: mode)
                                }
                            }
                        }
                    }
                    RowDivider()
                    AppIconSettingRow(title: "Light app icon", selection: $settings.appIcons.light,
                                      subtitle: "Dock icon while Airdraft is open")
                    RowDivider()
                    AppIconSettingRow(title: "Dark app icon", selection: $settings.appIcons.dark)
                    RowDivider()
                    SettingRow(title: "Recording window") {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(106), spacing: 10), count: 3), spacing: 12) {
                            ForEach(HUDStyle.allCases) { style in
                                ChoiceTile(title: style.title, selected: settings.hudStyle == style, action: { settings.hudStyle = style }) {
                                    HUDPreview(style: style, timer: settings.hudTimer)
                                }
                            }
                        }
                    }
                    if settings.hudStyle != .none || search.isSearching {
                        RowDivider()
                        SettingRow(title: "Show timer", subtitle: settings.hudStyle == .none ? "Choose a recording window style" : nil) {
                            Toggle("Show timer", isOn: $settings.hudTimer.isEnabled)
                                .labelsHidden().toggleStyle(.softSwitch)
                                .disabled(settings.hudStyle == .none)
                        }
                        if settings.hudTimer.isEnabled || search.isSearching {
                            RowDivider()
                            SettingRow(title: "Timer position", subtitle: settings.hudStyle == .none ? "Choose a recording window style and enable Show timer" : !settings.hudTimer.isEnabled ? "Enable Show timer" : nil) {
                                SoftSegmentedPicker("Timer position", selection: $settings.hudTimer.position,
                                    options: HUDTimerOptions.Position.allCases.map { ($0, $0.title) }, width: 160)
                                    .disabled(settings.hudStyle == .none || !settings.hudTimer.isEnabled)
                            }
                        }
                    }
                }
            }

            PageSection("Keyboard shortcuts") {
                SettingsCard {
                    SettingRow(title: "Dictation", subtitle: settings.hotkeyBehavior == .hold
                               ? "Hold to record; release to stop"
                               : settings.triggerDelayMilliseconds > 0 ? "Hold to start; press to stop" : "Press to start or stop") {
                        HotkeyRecorderView()
                    }
                    RowDivider()
                    SettingRow(title: "Push to talk or toggle") {
                        SoftSegmentedPicker("Shortcut behavior", selection: $settings.hotkeyBehavior,
                                            options: [(.hold, "Hold to talk"), (.toggle, "Toggle")], width: 200)
                    }
                    RowDivider()
                    SettingRow(title: "Trigger Delay", subtitle: "Short presses keep their normal action; 0 = off") {
                        SettingsNumberStepper(title: "Trigger Delay", value: $settings.triggerDelayMilliseconds,
                                              in: HotkeyTriggerState.delayRange, step: 50, unit: "ms")
                    }
                    RowDivider()
                    SettingRow(title: "Cancel recording", subtitle: "Discards the active recording") {
                        KeyCap(text: "esc")
                    }
                }
            }

            AutomationSettings()

            PageSection("Behavior") {
                SettingsCard {
                    SettingRow(title: "Read app context",
                               subtitle: "Sends window title, nearby text and selection to AI. Skips password fields and managers.") {
                        Toggle("Read app context", isOn: $settings.useAppContext).labelsHidden().toggleStyle(.softSwitch)
                    }
                    RowDivider()
                    SettingRow(title: "Maximum recording", subtitle: "Auto-stops and transcribes; 10 min maximum") {
                        SettingsNumberStepper(
                            title: "Maximum recording",
                            value: $settings.maxRecordingSeconds,
                            in: SpeechInputLimits.recordingSecondsRange,
                            step: 10,
                            unit: "s"
                        )
                    }
                }
            }

            PageSection("Live preview") {
                SettingsCard {
                    SettingRow(title: "Show text while speaking", subtitle: "On-device Apple Speech; final model unchanged") {
                        Toggle("Show text while speaking", isOn: $settings.livePreviewEnabled).labelsHidden().toggleStyle(.softSwitch)
                    }
                    if settings.livePreviewEnabled || search.isSearching {
                        RowDivider()
                        SettingRow(title: "Preview language", subtitle: !settings.livePreviewEnabled ? "Enable Show text while speaking; choose a language in Models" : settings.hudStyle == .none ? "Choose a recording window style" : "Choose and install a language in Models") {
                            Button("Open Models") { container.navigation.page = .models }.buttonStyle(SoftButtonStyle())
                        }
                    }
                }
            }

            PageSection("Audio history") {
                SettingsCard {
                    SettingRow(title: "Keep recordings", subtitle: "Local playback and retry. Off deletes audio, keeps text.") {
                        SoftPicker("Keep recordings", selection: Binding(get: { settings.audioRetention }, set: { choice in
                            let old = settings.audioRetention.cutoff() ?? .distantFuture
                            let new = choice.cutoff() ?? .distantFuture
                            if new > old { pendingRetention = choice; confirmRetention = true }
                            else { settings.audioRetention = choice }
                        }), width: 160) {
                            ForEach(AudioRetention.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    if let error = container.pipeline.audioStorageError {
                        RowDivider()
                        SettingRow(title: "Cleanup failed", subtitle: error) {
                            Button("Retry") { Task { await container.pipeline.pruneSavedAudio() } }
                                .buttonStyle(SoftButtonStyle())
                        }
                    }
                }
            }

            PageSection("Permissions") {
                SettingsCard {
                    SettingRow(title: "Microphone", subtitle: micStatus) {
                        if container.permissions.microphone != .authorized {
                            Button(container.permissions.microphone == .notDetermined ? "Request…" : "Open Settings…") {
                                if container.permissions.microphone == .notDetermined {
                                    Task { await container.permissions.requestMicrophone() }
                                } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                                .buttonStyle(SoftButtonStyle())
                        } else {
                            StatusDot(.ok)
                        }
                    }
                    RowDivider()
                    SettingRow(title: "Accessibility", subtitle: "Cursor insertion, app context, modifier shortcuts and Trigger Delay") {
                        if container.permissions.accessibilityGranted {
                            StatusDot(.ok)
                        } else {
                            AccessibilityPermissionActions()
                        }
                    }
                }
            }

            DataCleanupSettings()

            UpdateSettings(updates: container.updates)
        }
        .confirmationDialog("Remove older saved dictation audio?", isPresented: $confirmRetention, titleVisibility: .visible) {
            Button("Change Retention", role: .destructive) {
                if let pendingRetention { settings.audioRetention = pendingRetention }
                pendingRetention = nil
            }
            Button("Cancel", role: .cancel) { pendingRetention = nil }
        } message: {
            Text("Choosing \(pendingRetention?.title ?? "this limit") removes dictation audio outside that limit. Text and exported files stay. Deleted audio cannot be restored.")
        }
    }

    private var micStatus: String {
        switch container.permissions.microphone {
        case .authorized: return "Granted · \(container.microphones.label(container.settings.microphone))"
        case .denied: return "Denied · allow in System Settings"
        case .restricted: return "Restricted"
        default: return "Not requested yet"
        }
    }
}

private struct AppIconSettingRow: View {
    let title: String
    @Binding var selection: AppIconStyle
    var subtitle: String? = nil

    var body: some View {
        SettingRow(title: title, subtitle: subtitle) {
            HStack(spacing: 8) {
                Image(selection.assetName)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
                SoftPicker(title, selection: $selection, width: 146) {
                    ForEach(AppIconStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
            }
        }
    }
}

/// Tiny window mock-up for the theme picker.
struct ThemePreview: View {
    let mode: AppearanceMode

    var body: some View {
        ZStack {
            switch mode {
            case .light: window(dark: false)
            case .dark: window(dark: true)
            case .auto:
                window(dark: false)
                window(dark: true).mask {
                    GeometryReader { geometry in
                        Path { path in
                            path.move(to: CGPoint(x: geometry.size.width, y: 0))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                            path.addLine(to: CGPoint(x: 0, y: geometry.size.height))
                            path.closeSubpath()
                        }
                    }
                }
            }
        }
    }

    private func window(dark: Bool) -> some View {
        ZStack {
            LinearGradient(colors: dark ? [Color(white: 0.16), Color(white: 0.10)] : [Color(white: 0.96), Color(white: 0.88)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Circle().fill(.yellow).frame(width: 6, height: 6)
                    Circle().fill(.green).frame(width: 6, height: 6)
                }
                RoundedRectangle(cornerRadius: 3).fill(dark ? Color.white.opacity(0.14) : Color.black.opacity(0.10)).frame(width: 60, height: 8)
                RoundedRectangle(cornerRadius: 3).fill(dark ? Color.white.opacity(0.09) : Color.black.opacity(0.06)).frame(width: 84, height: 24)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// Preview tile for the recording-window picker.
struct HUDPreview: View {
    let style: HUDStyle
    var timer = HUDTimerOptions()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = Date()

    var body: some View {
        ZStack {
            Color.primary.opacity(0.05)
            switch style {
            case .mini:
                IndicatorView(snapshot: HUDSnapshot(state: .recording, levels: HUDPreview.sample, elapsed: 4.2), style: .mini, timer: timer)
                    .scaleEffect(0.55)
            case .cube, .sonic:
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || RenderMode.isActive)) { context in
                    let time = reduceMotion || RenderMode.isActive ? 1.4 : context.date.timeIntervalSince(started)
                    let level = Float(0.08 + 0.55 * pow(0.5 + 0.5 * sin(time * 2.8), 2))
                    IndicatorView(snapshot: HUDSnapshot(state: .recording, levels: Array(repeating: level, count: 22),
                                                        elapsed: 4.2, visualizerTime: time), style: style, timer: timer)
                        .scaleEffect(0.65)
                }
            case .none:
                Image(systemName: "eye.slash").font(.system(size: 22)).foregroundStyle(.secondary)
            }
        }
    }

    static let sample: [Float] = (0..<DictationPipeline.levelHistoryLength).map { Float(0.2 + 0.7 * abs(sin(Double($0) * 0.8))) }
}
