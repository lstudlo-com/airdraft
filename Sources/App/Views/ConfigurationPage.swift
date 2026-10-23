import AVFoundation
import AirdraftCore
import SwiftUI

// Recording-window direction: extend the existing gray Settings surface.
// Every visible preset uses the same production capsule and a 1.2× specimen.
// Classic scrolls, Orbit rotates silver rings, and Silk folds a metallic ribbon.
// A title above two right-aligned rows keeps six choices readable at 784 points.
// Finish with native motion/geometry checks and light/dark minimum/tall captures.
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
                    SettingRow(title: "Text size", subtitle: "The menu and recording window keep their size") {
                        SoftSegmentedPicker("Text size", selection: $settings.textSize,
                            options: TextSizePreference.allCases.map { ($0, $0.title) }, width: 240)
                            .accessibilityIdentifier("settings.textSize")
                    }
                    RowDivider()
                    AppIconSettingRow(title: "Light app icon", selection: $settings.appIcons.light,
                                      subtitle: "Dock icon while Airdraft is open")
                    RowDivider()
                    AppIconSettingRow(title: "Dark app icon", selection: $settings.appIcons.dark)
                    RowDivider()
                    SettingRow(title: "Recording window", stacked: true) {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(HUDPreview.tileWidth), spacing: 10), count: 3), spacing: 12) {
                            ForEach(HUDStyle.allCases) { style in
                                ChoiceTile(title: style.title, selected: settings.hudStyle == style,
                                           action: { settings.hudStyle = style }, previewSize: HUDPreview.size) {
                                    HUDPreview(style: style, timer: settings.hudTimer, discoEnabled: settings.hudDiscoEnabled)
                                }
                            }
                        }
                        .frame(width: HUDPreview.tileWidth * 3 + 20)
                    }
                    if settings.hudStyle != .none || search.isSearching {
                        RowDivider()
                        SettingRow(title: "Disco", detail: settings.hudStyle == .none ? String(localized: "Choose a recording window style") : String(localized: "Colors flow with your voice")) {
                            Toggle("Disco", isOn: $settings.hudDiscoEnabled)
                                .labelsHidden().toggleStyle(.softSwitch)
                                .disabled(settings.hudStyle == .none)
                                .accessibilityIdentifier("settings.hudDisco")
                        }
                        RowDivider()
                        SettingRow(title: "Show timer", subtitle: settings.hudStyle == .none ? "Choose a recording window style" : nil) {
                            Toggle("Show timer", isOn: $settings.hudTimer.isEnabled)
                                .labelsHidden().toggleStyle(.softSwitch)
                                .disabled(settings.hudStyle == .none)
                        }
                        if settings.hudTimer.isEnabled || search.isSearching {
                            RowDivider()
                            SettingRow(title: "Timer position", detail: settings.hudStyle == .none ? String(localized: "Choose a recording window style and enable Show timer") : !settings.hudTimer.isEnabled ? String(localized: "Enable Show timer") : nil) {
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
                    SettingRow(title: "Dictation", detail: settings.hotkeyBehavior == .hold
                               ? String(localized: "Hold to record; release to stop")
                               : settings.triggerDelayMilliseconds > 0 ? String(localized: "Hold to start; press to stop") : String(localized: "Press to start or stop")) {
                        HotkeyRecorderView()
                    }
                    RowDivider()
                    SettingRow(title: "Push to talk or toggle") {
                        SoftSegmentedPicker("Shortcut behavior", selection: $settings.hotkeyBehavior,
                                            options: [(.hold, String(localized: "Hold to talk")), (.toggle, String(localized: "Toggle"))], width: 200)
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
                    SettingRow(title: "Vocabulary in speech recognition",
                               subtitle: "Supported on-device models favor your spellings. Online services always receive them.") {
                        Toggle("Vocabulary in speech recognition", isOn: $settings.vocabularyBiasesOnDeviceSpeech)
                            .labelsHidden().toggleStyle(.softSwitch)
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
                    SettingRow(title: "Show text while speaking", subtitle: "On this Mac; final transcript unchanged") {
                        Toggle("Show text while speaking", isOn: $settings.livePreviewEnabled).labelsHidden().toggleStyle(.softSwitch)
                    }
                    if settings.livePreviewEnabled || search.isSearching {
                        RowDivider()
                        SettingRow(title: "Preview source", detail: settings.livePreviewEnabled ? nil : String(localized: "Enable Show text while speaking")) {
                            SoftPicker("Preview source", selection: $settings.livePreviewSource, width: 200) {
                                ForEach(LivePreviewSource.allCases) { Text($0.title).tag($0) }
                            }
                            .disabled(!settings.livePreviewEnabled)
                        }
                        if settings.livePreviewSource == .appleSpeech || search.isSearching {
                            RowDivider()
                            SettingRow(title: "Preview language", detail: !settings.livePreviewEnabled ? String(localized: "Enable Show text while speaking; choose a language in Models") : settings.livePreviewSource != .appleSpeech ? String(localized: "Choose Apple Speech as the preview source") : settings.hudStyle == .none ? String(localized: "Choose a recording window style") : String(localized: "Choose and install a language in Models")) {
                                Button("Open Models") { container.navigation.page = .models }.buttonStyle(SoftButtonStyle())
                            }
                        }
                        if settings.livePreviewSource == .speechModel || search.isSearching {
                            let readiness = container.modelPreviewReadiness
                            RowDivider()
                            SettingRow(title: "Preview model", detail: modelPreviewDetail(readiness)) {
                                switch readiness {
                                case .unavailable:
                                    Button("Open Models") { container.navigation.page = .models }.buttonStyle(SoftButtonStyle())
                                case .checking:
                                    StatusDot(.busy)
                                case .ready:
                                    StatusDot(settings.livePreviewEnabled && settings.livePreviewSource == .speechModel ? .ok : .inactive)
                                }
                            }
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
                        SettingRow(title: "Cleanup failed", detail: error) {
                            Button("Retry") { Task { await container.pipeline.pruneSavedAudio() } }
                                .buttonStyle(SoftButtonStyle())
                        }
                    }
                }
            }

            PageSection("Permissions") {
                SettingsCard {
                    SettingRow(title: "Microphone", detail: micStatus) {
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
            Text("Choosing \(pendingRetention?.title ?? String(localized: "this limit")) removes dictation audio outside that limit. Text and exported files stay. Deleted audio cannot be restored.")
        }
    }

    private var micStatus: String {
        switch container.permissions.microphone {
        case .authorized: return String(localized: "Granted · \(container.microphones.label(container.settings.microphone))")
        case .denied: return String(localized: "Denied · allow in System Settings")
        case .restricted: return String(localized: "Restricted")
        default: return String(localized: "Not requested yet")
        }
    }
}

private struct AppIconSettingRow: View {
    let title: LocalizedStringResource
    @Binding var selection: AppIconStyle
    var subtitle: LocalizedStringResource? = nil

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
extension ConfigurationPage {
    /// The model preview row names the active profile's speech model, or why it cannot preview.
    func modelPreviewDetail(_ readiness: ModelPreviewReadiness) -> String {
        let settings = container.settings
        if !settings.livePreviewEnabled { return String(localized: "Enable Show text while speaking") }
        if settings.livePreviewSource != .speechModel { return String(localized: "Choose Selected speech model as the preview source") }
        switch readiness {
        case .unavailable(let reason): return reason
        case .checking: return String(localized: "Checking model files…")
        case .ready: return container.speechConfig.displayName
        }
    }
}

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
    static let specimenScale: CGFloat = 0.65 * 1.2
    static let size = CGSize(width: 96 * 1.2, height: 60 * 1.2)
    static let tileWidth = size.width + 10
    let style: HUDStyle
    var timer = HUDTimerOptions()
    var discoEnabled = false
    /// A fixed phase lets the native fixture capture the actual Settings preview.
    var frozenTime: TimeInterval?
    var reduceMotionOverride: Bool?
    var renderModeOverride: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var started = Date()
    @State private var disco = HUDDiscoMotion()

    private var pausesMotion: Bool {
        (reduceMotionOverride ?? reduceMotion) || (renderModeOverride ?? RenderMode.isActive)
            || frozenTime != nil || scenePhase != .active
    }

    var body: some View {
        ZStack {
            Color.primary.opacity(0.05)
            switch style {
            case .classic, .cube, .sonic, .orbit, .silk:
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: pausesMotion)) { context in
                    let time = frozenTime ?? (pausesMotion ? 0.5 : context.date.timeIntervalSince(started))
                    let samples = Self.samples(at: time)
                    let energy = SpatialHUDMotion.energy(levels: samples, recording: true)
                    IndicatorView(snapshot: HUDSnapshot(state: .recording, levels: samples,
                                                        elapsed: 4.2, visualizerTime: time,
                                                        visualizerDisco: pausesMotion ? .still(energy: energy) : disco.frame),
                                  style: style, timer: timer, discoEnabled: discoEnabled)
                        .scaleEffect(Self.specimenScale)
                        .onChange(of: context.date, initial: true) { _, date in
                            guard discoEnabled, !pausesMotion else { return }
                            disco.advance(to: date.timeIntervalSinceReferenceDate, target: energy)
                        }
                }
            case .none:
                Image(systemName: "eye.slash").font(.system(size: 22)).foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    static func samples(at time: TimeInterval) -> [Float] {
        (0..<DictationPipeline.levelHistoryLength).map { index in
            let t = time - Double(DictationPipeline.levelHistoryLength - 1 - index) * 0.055
            let phrase = pow(0.5 + 0.5 * sin(t * 2.8), 2)
            let syllable = 0.25 + 0.75 * pow(0.5 + 0.5 * sin(t * 17.3), 2)
            return Float(0.04 + 0.62 * phrase * syllable)
        }
    }
}
