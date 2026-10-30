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
                    InterfaceLanguageRow(store: container.interfaceLanguage)
                    RowDivider()
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
                                    HUDPreview(style: style, timer: settings.hudTimer, discoEnabled: settings.hudDiscoEnabled,
                                               discoIntensity: settings.hudDiscoIntensity)
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
                        if settings.hudDiscoEnabled || search.isSearching {
                            RowDivider()
                            SettingRow(title: "Disco intensity",
                                       detail: settings.hudStyle == .none ? String(localized: "Choose a recording window style and enable Disco")
                                           : !settings.hudDiscoEnabled ? String(localized: "Enable Disco") : nil) {
                                DiscoIntensitySlider(value: $settings.hudDiscoIntensity)
                                    .disabled(settings.hudStyle == .none || !settings.hudDiscoEnabled)
                            }
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
                    ExtraShortcutRows()
                }
            }

            SendSettings()

            AutomationSettings()

            PageSection("Behavior") {
                SettingsCard {
                    SettingRow(title: "Read app context",
                               subtitle: "Sends window title, nearby text and selection to AI. Skips password fields and managers.") {
                        Toggle("Read app context", isOn: $settings.useAppContext).labelsHidden().toggleStyle(.softSwitch)
                    }
                    TelemetrySettingRow()
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
                    SettingRow(title: "Show text while speaking", subtitle: "Becomes the transcript when it matches your model") {
                        Toggle("Show text while speaking", isOn: $settings.livePreviewEnabled).labelsHidden().toggleStyle(.softSwitch)
                    }
                    if settings.livePreviewEnabled || search.isSearching {
                        let liveTextOff = !settings.livePreviewEnabled ? String(localized: "Enable Show text while speaking")
                            : settings.hudStyle == .none ? String(localized: "Choose a recording window style") : nil
                        RowDivider()
                        SettingRow(title: "Live text style", detail: liveTextOff, stacked: true) {
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(HUDPreview.tileWidth), spacing: 10), count: 3), spacing: 12) {
                                ForEach(LiveTextOptions.Style.allCases) { style in
                                    ChoiceTile(title: style.title, selected: settings.liveText.style == style,
                                               action: { settings.liveText.style = style }, previewSize: HUDPreview.size) {
                                        LiveTextStylePreview(options: LiveTextOptions(style: style, lines: settings.liveText.lines,
                                                                                      textSize: settings.liveText.textSize))
                                    }
                                }
                            }
                            .frame(width: HUDPreview.tileWidth * 3 + 20)
                            .disabled(liveTextOff != nil)
                        }
                        RowDivider()
                        SettingRow(title: "Text animation", detail: liveTextOff, stacked: true) {
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(HUDPreview.tileWidth), spacing: 10), count: 3), spacing: 12) {
                                ForEach(LiveTextOptions.Reveal.allCases) { reveal in
                                    ChoiceTile(title: reveal.title, selected: settings.liveText.reveal == reveal,
                                               action: { settings.liveText.reveal = reveal }, previewSize: HUDPreview.size) {
                                        LiveTextRevealPreview(options: LiveTextOptions(style: settings.liveText.style, lines: 2,
                                                                                       textSize: settings.liveText.textSize,
                                                                                       reveal: reveal))
                                    }
                                }
                            }
                            .frame(width: HUDPreview.tileWidth * 3 + 20)
                            .disabled(liveTextOff != nil)
                        }
                        RowDivider()
                        SettingRow(title: "Lines", detail: liveTextOff) {
                            SoftSegmentedPicker("Lines", selection: $settings.liveText.lines,
                                options: LiveTextOptions.lineRange.map { ($0, $0.formatted()) }, width: 160)
                                .disabled(liveTextOff != nil)
                        }
                        RowDivider()
                        SettingRow(title: "Live text size", detail: liveTextOff) {
                            SoftSegmentedPicker("Live text size", selection: $settings.liveText.textSize,
                                options: LiveTextOptions.TextSize.allCases.map { ($0, $0.title) }, width: 240)
                                .disabled(liveTextOff != nil)
                        }
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

/// Gentle at the leading end, vivid at the trailing end; 50% is the original palette.
private struct DiscoIntensitySlider: View {
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 8) {
            Text("Gentle", comment: "Disco intensity slider, lowest end").supportingText().fixedSize()
            SoftSlider(title: "Disco intensity", value: $value, range: 0...1, step: 0.05, keyboardStep: 0.1,
                       valueDescription: { $0.formatted(.percent.precision(.fractionLength(0))) })
                .frame(width: 160)
                .accessibilityIdentifier("settings.hudDiscoIntensity")
            Text("Vivid", comment: "Disco intensity slider, highest end").supportingText().fixedSize()
        }
    }
}

/// System Default follows the Mac; a language chosen here applies after relaunching.
private struct InterfaceLanguageRow: View {
    let store: InterfaceLanguageStore

    var body: some View {
        SettingRow(title: "Language",
                   detail: store.needsRelaunch ? String(localized: "Relaunch Airdraft to switch languages")
                       : String(localized: "Speech languages are set in Models")) {
            HStack(spacing: 8) {
                if store.needsRelaunch {
                    Button("Relaunch") { AppRelaunch.request() }
                        .primaryButtonStyle()
                        .accessibilityIdentifier("settings.interfaceLanguage.relaunch")
                }
                SoftPicker("Language", selection: Binding(get: { store.selection?.code ?? "" },
                                                          set: { code in store.select(InterfaceLanguage.shipped.first { $0.code == code }) }),
                           width: SoftPickerWidth.fitting([String(localized: "System Default")] + InterfaceLanguage.shipped.map(\.name),
                                                          minimum: 160)) {
                    Text("System Default").tag("")
                    ForEach(InterfaceLanguage.shipped) { language in
                        Text(verbatim: language.name).tag(language.code)
                    }
                }
                .accessibilityIdentifier("settings.interfaceLanguage")
            }
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
                SoftPicker(title, selection: $selection,
                           width: SoftPickerWidth.fitting(AppIconStyle.allCases.map(\.title), minimum: 146)) {
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
        case .ready:
            let speech = container.speechConfig
            let name = speech.displayName
            // AD-123: say what live text costs and whether it is the transcript.
            guard !speech.kind.isLocal else {
                return String(localized: "\(name). Live text becomes the transcript, so it isn’t transcribed again.")
            }
            let provider = speech.kind.preset?.name ?? speech.kind.rawValue
            if ModelSpeechPreview.liveTextBecomesTranscript(speech) {
                return String(localized: "\(name). Streams audio to \(provider) while you speak; live text becomes the transcript.")
            }
            return String(localized: "\(name). Streams audio to \(provider) while you speak, then sends the recording again for the transcript, so it’s billed twice.")
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

/// Preview tile for the live-text style picker: the style on a flat mid-gray
/// desktop, where the light and the dark styles both read.
struct LiveTextStylePreview: View {
    let options: LiveTextOptions

    static let backdrop = Color(white: 0.42)
    static let sample = String(localized: "Live text appears here while you speak, newest line last.")

    var body: some View {
        Self.specimen(text: Self.sample, options: options)
            .accessibilityHidden(true)
    }

    static func specimen(text: String?, options: LiveTextOptions) -> some View {
        let scale = (HUDPreview.size.width - 12) / LivePreviewCard.width(for: options.style)
        return ZStack {
            backdrop
            LivePreviewCard(text: text, options: options)
                .environment(\.liveTextStill, RenderMode.isActive)
                .fixedSize()
                .scaleEffect(scale)
                .frame(width: HUDPreview.size.width, height: HUDPreview.size.height)
        }
    }
}

/// Preview tile for the text-animation picker: the sample sentence arrives a few
/// words at a time with that effect, holds, and starts again. It rests on the whole
/// sentence in renders, inactive windows and Reduce Motion.
struct LiveTextRevealPreview: View {
    let options: LiveTextOptions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var started = Date()

    /// Seconds between updates, and the pause on the whole sentence.
    static let step: TimeInterval = 0.5
    static let hold: TimeInterval = 1.6

    private var paused: Bool { reduceMotion || RenderMode.isActive || scenePhase != .active }

    /// The sample split into the pieces a recognizer would send: two words at a time,
    /// using the language's own word breaks so Chinese and Japanese split too.
    static let updates: [String] = {
        var ends: [String.Index] = []
        LiveTextStylePreview.sample.enumerateSubstrings(in: LiveTextStylePreview.sample.startIndex...,
                                                        options: .byWords) { _, range, _, _ in ends.append(range.upperBound) }
        let sample = LiveTextStylePreview.sample
        var updates = stride(from: 1, to: ends.count, by: 2).map { String(sample[..<ends[$0]]) }
        updates.append(sample)
        return updates
    }()

    var body: some View {
        TimelineView(.periodic(from: started, by: Self.step / 2)) { context in
            LiveTextStylePreview.specimen(text: paused ? LiveTextStylePreview.sample : text(at: context.date),
                                          options: options)
        }
        .accessibilityHidden(true)
    }

    private func text(at date: Date) -> String {
        let cycle = Double(Self.updates.count) * Self.step + Self.hold
        let elapsed = date.timeIntervalSince(started).truncatingRemainder(dividingBy: cycle)
        return Self.updates[min(Self.updates.count - 1, Int(elapsed / Self.step))]
    }
}

struct HUDPreview: View {
    static let specimenScale: CGFloat = 0.65 * 1.2
    static let size = CGSize(width: 96 * 1.2, height: 60 * 1.2)
    static let tileWidth = size.width + 10
    let style: HUDStyle
    var timer = HUDTimerOptions()
    var discoEnabled = false
    var discoIntensity = AppSettings.defaultDiscoIntensity
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
                                                        visualizerDisco: pausesMotion ? .still(energy: energy, intensity: discoIntensity) : disco.frame),
                                  style: style, timer: timer, discoEnabled: discoEnabled)
                        .scaleEffect(Self.specimenScale)
                        .onChange(of: context.date, initial: true) { _, date in
                            guard discoEnabled, !pausesMotion else { return }
                            disco.advance(to: date.timeIntervalSinceReferenceDate, target: energy, intensity: discoIntensity)
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
