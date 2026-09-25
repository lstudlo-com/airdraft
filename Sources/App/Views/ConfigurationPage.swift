import AVFoundation
import AirdraftCore
import SwiftUI

struct ConfigurationPage: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        @Bindable var settings = container.settings
        PageScaffold(.configuration) {
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
                    SettingRow(title: "Recording window") {
                        HStack(spacing: 10) {
                            ForEach(HUDStyle.allCases) { style in
                                ChoiceTile(title: style.title, selected: settings.hudStyle == style, action: { settings.hudStyle = style }) {
                                    HUDPreview(style: style)
                                }
                            }
                        }
                    }
                }
            }

            PageSection("Keyboard shortcuts") {
                SettingsCard {
                    SettingRow(title: "Dictation", subtitle: settings.hotkeyBehavior == .hold ? "Hold to record, release when done" : "Press to start, press again to stop") {
                        HotkeyRecorderView()
                    }
                    RowDivider()
                    SettingRow(title: "Push to talk or toggle") {
                        Picker("Shortcut behavior", selection: $settings.hotkeyBehavior) {
                            Text("Hold to talk").tag(HotkeyBehavior.hold)
                            Text("Toggle").tag(HotkeyBehavior.toggle)
                        }
                        .pickerStyle(.segmented)
                        .settingsPicker(width: 200)
                    }
                    RowDivider()
                    SettingRow(title: "Cancel recording", subtitle: "Discards the active recording") {
                        KeyCap(text: "esc")
                    }
                }
            }

            PageSection("Behavior") {
                SettingsCard {
                    SettingRow(title: "Insert text via") {
                        Picker("Insert text via", selection: $settings.insertionMethod) {
                            Text("Accessibility, then paste").tag(InsertionMethod.auto)
                            Text("Always paste").tag(InsertionMethod.paste)
                        }
                        .settingsPicker(width: 220)
                    }
                    RowDivider()
                    SettingRow(title: "Read app context",
                               subtitle: "Sends the window title, nearby text and selection with the transcript to your refinement provider. Password fields and password managers are skipped.") {
                        Toggle("Read app context", isOn: $settings.useAppContext).labelsHidden().toggleStyle(.switch)
                    }
                    RowDivider()
                    SettingRow(title: "Maximum recording", subtitle: settings.asr.kind == .groq ? "Groq recordings stop after 740 s to stay within its upload limit" : nil) {
                        SettingsNumberStepper(
                            title: "Maximum recording",
                            value: $settings.maxRecordingSeconds,
                            in: 10...1800,
                            step: 10,
                            unit: "s"
                        )
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
                    SettingRow(title: "Accessibility", subtitle: "Cursor insertion, app context, modifier-only shortcuts") {
                        if container.permissions.accessibilityGranted {
                            StatusDot(.ok)
                        } else {
                            AccessibilityPermissionActions()
                        }
                    }
                }
            }

            UpdateSettings(updates: container.updates)
        }
    }

    private var micStatus: String {
        switch container.permissions.microphone {
        case .authorized: return "Granted · \(container.microphones.label(container.settings.microphone))"
        case .denied: return "Denied. Enable it in System Settings ▸ Privacy & Security ▸ Microphone"
        case .restricted: return "Restricted"
        default: return "Not requested yet"
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

    var body: some View {
        ZStack {
            Color.primary.opacity(0.05)
            switch style {
            case .classic:
                IndicatorView(snapshot: HUDSnapshot(state: .recording, levels: HUDPreview.sample, elapsed: 4.2), style: .classic)
                    .scaleEffect(0.5)
            case .mini:
                IndicatorView(snapshot: HUDSnapshot(state: .recording, levels: HUDPreview.sample, elapsed: 4.2), style: .mini)
                    .scaleEffect(0.55)
            case .none:
                Image(systemName: "eye.slash").font(.system(size: 22)).foregroundStyle(.secondary)
            }
        }
    }

    static let sample: [Float] = (0..<DictationPipeline.levelHistoryLength).map { Float(0.2 + 0.7 * abs(sin(Double($0) * 0.8))) }
}
