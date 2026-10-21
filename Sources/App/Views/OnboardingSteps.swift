import AirdraftCore
import AppKit
import AVFoundation
import SwiftUI

// MARK: Welcome

struct OnboardingWelcomeStep: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        Card(padding: 24) {
            OnboardingWelcomeDemo(hotkey: container.settings.hotkey, behavior: container.settings.hotkeyBehavior)
        }
        SettingsCard {
            fact("lock", "Private when you want it", "Speech can be turned into text entirely on this Mac.")
            RowDivider()
            fact("app.badge", "Works in your apps", "Mail, Messages, Notes, Slack, your browser and more.")
            RowDivider()
            fact("arrow.uturn.backward", "Nothing is permanent", "Every choice here can be changed later in Settings and Models.")
        }
    }

    private func fact(_ symbol: String, _ title: LocalizedStringResource, _ detail: LocalizedStringResource) -> some View {
        HStack(spacing: Theme.controlSpacing) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background { NeumorphicSurface(shape: RoundedRectangle(cornerRadius: 8, style: .continuous), inset: true, depth: 1.5) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).supportingText()
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: Speech

struct OnboardingSpeechStep: View {
    @Environment(AppContainer.self) private var container
    @Bindable var speech: OnboardingSpeechChoice

    private var busy: Bool { container.pipeline.isBusy }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.controlSpacing + 4) {
            OnboardingChoiceCard(
                title: "On this Mac", symbol: "laptopcomputer", badge: "Recommended",
                points: ["Your voice never leaves this Mac.",
                         "Free, and works without internet.",
                         "One-time download of \(speech.entry.downloadSize)."],
                selected: !speech.useCloud) { speech.useCloud = false }
                .accessibilityIdentifier("onboarding.speech-local")
            OnboardingChoiceCard(
                title: "Online service", symbol: "cloud",
                points: ["Uses your own API key from a provider such as Groq or OpenAI.",
                         "The provider bills you for what you use.",
                         "No download. Helpful on older Macs."],
                selected: speech.useCloud) { speech.useCloud = true }
                .accessibilityIdentifier("onboarding.speech-cloud")
        }
        .fixedSize(horizontal: false, vertical: true)
        .disabled(busy)

        if speech.useCloud { cloud } else { local }

        SettingsCard {
            SpeechLanguageSettings(configuration: speech.config)
        }
        .disabled(busy)
    }

    private var local: some View {
        SettingsCard {
            HStack(spacing: Theme.controlSpacing) {
                ModelBrandIcon(brand: speech.entry.brand)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(speech.entry.title).font(.system(size: 13, weight: .medium))
                        if speech.entry.id == speech.recommendation { PillTag(text: "BEST FIT") }
                    }
                    Text("\(speech.entry.note) \(speech.entry.tags.joined(separator: " · "))").supportingText()
                }
                Spacer(minLength: 8)
                downloadAction
            }
            if let current = speech.download?.progress, !speech.localInstalled {
                ModelDownloadProgress(progress: current)
                Text("You can keep going. Setup continues while it downloads.").supportingText()
            }
            if let error = speech.download?.error, !speech.localInstalled {
                Text(error).supportingText().textSelection(.enabled)
            }
            RowDivider()
            SettingRow(title: "Use a different model") {
                SoftPicker("Speech model", selection: $speech.localChoice, width: 210) {
                    ForEach(ModelCatalogue.entries.filter(\.isDownloadable)) { Text($0.title).tag($0.id) }
                }
                .disabled(busy)
            }
        }
        .onChange(of: speech.localChoice) { _, _ in speech.refreshInstalled() }
    }

    @ViewBuilder private var downloadAction: some View {
        if speech.localInstalled {
            Label("Downloaded", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        } else if speech.download?.progress != nil {
            Button("Cancel") { container.downloads.cancel(speech.localConfig) }
                .buttonStyle(SoftButtonStyle())
        } else {
            Button(speech.download?.error == nil ? "Download" : "Retry Download") {
                let container = container
                container.downloads.start(speech.localConfig) { container.applyOnboardingSpeechIfReady() }
            }
            .primaryButtonStyle()
            .accessibilityIdentifier("onboarding.download")
        }
    }

    private var cloud: some View {
        SettingsCard {
            SettingRow(title: "Provider") {
                SoftPicker("Provider", selection: $speech.cloudChoice, width: 180) {
                    ForEach(EndpointPreset.asr) { Text($0.name).tag($0.kind) }
                }
            }
            RowDivider()
            SpeechKeyRows(preset: speech.preset, config: speech.config)
            RowDivider()
            Text("Get a key from the provider’s website, paste it here, then press Test. Your key stays in this Mac’s Keychain.")
                .supportingText().fixedSize(horizontal: false, vertical: true)
        }
        .disabled(busy)
    }
}

private extension ModelEntry {
    var downloadSize: String {
        if case .download(let size) = storage { return size }
        return String(localized: "language files")
    }
}

// MARK: Permissions

struct OnboardingPermissionsStep: View {
    @Environment(AppContainer.self) private var container
    @State private var previews = MicrophoneLevelPreviews()
    @State private var visible = false
    @State private var heard = false
    @State private var showingHelp = false

    /// Renders can show either state without changing this Mac's permissions.
    private static var forced: String? { RenderMode.value("ONBOARDING_PERMISSIONS") }
    static func microphoneGranted(_ container: AppContainer) -> Bool {
        forced.map { $0 == "granted" } ?? (container.permissions.microphone == .authorized)
    }
    static func accessibilityGranted(_ container: AppContainer) -> Bool {
        forced.map { $0 == "granted" } ?? container.permissions.accessibilityGranted
    }

    private var micGranted: Bool { Self.microphoneGranted(container) }
    private var axGranted: Bool { Self.accessibilityGranted(container) }
    private var busy: Bool { container.pipeline.isBusy }
    private var device: Microphone? {
        container.settings.microphone.resolve(in: container.microphones.devices,
                                              systemDefaultID: container.microphones.systemDefaultID)
    }
    private var level: Float {
        if RenderMode.isActive { return micGranted ? 0.45 : 0 }
        return device.flatMap { previews.levels[$0.uid] } ?? 0
    }

    var body: some View {
        SettingsCard {
            header("Microphone", detail: "So Airdraft can hear you while you dictate.", ready: micGranted) {
                Button(container.permissions.microphone == .notDetermined ? "Allow Microphone" : "Open System Settings") {
                    if container.permissions.microphone == .notDetermined {
                        Task { await container.permissions.requestMicrophone(); synchronize() }
                    } else {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                    }
                }
                .buttonStyle(SoftButtonStyle())
                .accessibilityIdentifier("onboarding.allow-microphone")
            }
            if micGranted {
                RowDivider()
                SettingRow(title: "Input") { MicrophonePicker(width: 220) }
                OnboardingVoiceWell(level: level)
                if let error = device.flatMap({ previews.errors[$0.uid] }) {
                    Text(error).supportingText().textSelection(.enabled)
                } else {
                    Label(heard ? "Airdraft can hear you." : "Say something. The bars should move.",
                          systemImage: heard ? "checkmark.circle.fill" : "mic")
                        .supportingText()
                        .accessibilityIdentifier("onboarding.microphone-check")
                }
            }
        }

        SettingsCard {
            header("Accessibility", detail: "So Airdraft can type your words into other apps.", ready: axGranted) {
                Button("Open System Settings") { container.openAccessibilitySettings() }
                    .buttonStyle(SoftButtonStyle())
                    .accessibilityIdentifier("onboarding.open-accessibility")
            }
            if !axGranted {
                RowDivider()
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        instruction(1, "Click Open System Settings.")
                        instruction(2, "Find Airdraft in the list and turn its switch on.")
                        instruction(3, "Come back here. This page notices by itself.")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    OnboardingAccessibilitySwitch(granted: axGranted)
                        .frame(width: 210)
                }
                RowDivider()
                NoticeRow("Switch already on, or Airdraft is missing from the list?") {
                    Button("Get Help") { showingHelp = true }
                        .buttonStyle(SoftButtonStyle())
                }
            }
        }
        .sheet(isPresented: $showingHelp) { AccessibilityPermissionHelp() }

        HStack(spacing: 6) {
            Image(systemName: "hand.raised")
            Text("Airdraft records only while you use your shortcut, and never reads your screen unless you turn that on.")
        }
        .supportingText()
        .padding(.leading, Theme.sectionTitleLeadingInset)
        .onAppear {
            visible = true
            container.microphones.refresh()
            container.permissions.refresh()
            synchronize()
        }
        .onDisappear {
            visible = false
            previews.stop()
        }
        .onChange(of: busy) { _, _ in synchronize() }
        .onChange(of: container.permissions.microphone) { _, _ in synchronize() }
        .onChange(of: container.settings.microphone) { _, _ in heard = false; synchronize() }
        .onChange(of: container.microphones.devices) { _, _ in synchronize() }
        .onChange(of: container.microphones.systemDefaultID) { _, _ in synchronize() }
        .onChange(of: level) { _, value in if value > 0.12 { heard = true } }
    }

    /// Previews only the microphone that dictation will use, and never while busy.
    private func synchronize() {
        guard visible, !RenderMode.isActive, !busy, container.permissions.microphone == .authorized,
              let device else {
            previews.stop()
            return
        }
        previews.synchronize(devices: [device], selection: container.settings.microphone,
                             systemDefaultID: container.microphones.systemDefaultID)
    }

    private func header<Action: View>(_ title: LocalizedStringResource, detail: LocalizedStringResource, ready: Bool,
                                      @ViewBuilder action: () -> Action) -> some View {
        HStack(spacing: Theme.controlSpacing) {
            StatusDot(ok: ready)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                (ready ? Text("Allowed") : Text(detail)).supportingText()
            }
            Spacer()
            if !ready { action() }
        }
        .accessibilityElement(children: .contain)
    }

    private func instruction(_ number: Int, _ text: LocalizedStringResource) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background { NeumorphicSurface(shape: Circle(), inset: true, depth: 1.2) }
            Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: Shortcut

struct OnboardingShortcutStep: View {
    @Environment(AppContainer.self) private var container
    @Binding var practiced: Bool
    @State private var monitor = HotkeyRehearsalMonitor()

    private var hotkey: Hotkey { container.settings.hotkey }
    private var behavior: HotkeyBehavior { container.settings.hotkeyBehavior }
    private var verb: String {
        behavior.instructionVerb(triggerDelayMilliseconds: container.settings.triggerDelayMilliseconds)
    }

    var body: some View {
        @Bindable var settings = container.settings
        Card(padding: 28) {
            VStack(spacing: 18) {
                OnboardingKeyCaps(hotkey: hotkey, lit: monitor.rehearsal.litCaps, size: 64)
                    .accessibilityIdentifier("onboarding.keycaps")
                Group {
                    if practiced {
                        Label(behavior == .hold ? "That’s it. Hold to talk, let go to insert." : "That’s it. Press to start, press again to insert.",
                              systemImage: "checkmark.circle.fill")
                    } else {
                        Text(hotkey.keyCaps.count > 1
                             ? "\(verb) \(OnboardingKeyNames.spoken(hotkey)) together."
                             : "\(verb) \(OnboardingKeyNames.spoken(hotkey)).")
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(practiced ? .secondary : .primary)
                .accessibilityIdentifier("onboarding.shortcut-status")
            }
            .frame(maxWidth: .infinity)
        }

        SettingsCard {
            SettingRow(title: "Shortcut", subtitle: "Pick keys you can reach without looking.") {
                HotkeyRecorderView()
            }
            RowDivider()
            SettingRow(title: "How it works", detail: behavior == .hold
                       ? String(localized: "Hold while you speak. Good for short messages.")
                       : String(localized: "Press once to start and again to stop. Good for longer thoughts.")) {
                SoftSegmentedPicker("Shortcut behavior", selection: $settings.hotkeyBehavior,
                                    options: [(.hold, String(localized: "Hold to talk")), (.toggle, String(localized: "Toggle"))], width: 200)
            }
            RowDivider()
            SettingRow(title: "Cancel a recording", subtitle: "Throws away what you just said.") {
                KeyCap(text: "esc")
            }
            if FnKeyUsage.conflicts(with: hotkey) {
                RowDivider()
                NoticeRow("macOS also uses the fn key. Set “Press 🌐 key to” to Do Nothing so it starts Airdraft instead.") {
                    Button("Open Keyboard Settings") { FnKeyUsage.openSettings() }
                        .buttonStyle(SoftButtonStyle())
                }
            }
        }
        .onAppear { monitor.start(container) }
        .onDisappear { monitor.stop() }
        .onChange(of: hotkey) { _, _ in practiced = false; monitor.start(container) }
        .onChange(of: monitor.rehearsal.completedPresses) { _, count in if count > 0 { practiced = true } }
    }
}

/// Local key monitoring for practice. Real dictation is paused separately through
/// `HotkeyService.rehearsing`; this only lights the caps and counts full presses.
@MainActor @Observable
final class HotkeyRehearsalMonitor {
    private(set) var rehearsal = HotkeyRehearsal(hotkey: .controlOption)
    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var resign: NSObjectProtocol?
    /// Practice consumes the shortcut's own key so it cannot also press a focused button.
    @ObservationIgnored private var consumesKey = true

    func start(_ container: AppContainer, consumesKey: Bool = true) {
        stop()
        self.consumesKey = consumesKey
        rehearsal = HotkeyRehearsal(hotkey: container.settings.hotkey)
        let handler: (NSEvent) -> NSEvent? = { [weak self, weak container] event in
            // While the recorder captures a new shortcut, its own monitor owns the keys.
            guard let self, let container, !container.hotkeys.suspended else { return event }
            let kind: HotkeyPressState.Event = switch event.type {
            case .keyDown: .keyDown
            case .keyUp: .keyUp
            default: .flagsChanged
            }
            let flags = UInt64(event.modifierFlags.rawValue)
            self.rehearsal.handle(kind, keyCode: event.keyCode, flags: flags,
                                  isRepeat: kind == .keyDown && event.isARepeat)
            let ownKey = kind != .flagsChanged && !self.rehearsal.hotkey.isModifierOnly
                && event.keyCode == self.rehearsal.hotkey.keyCode
            return ownKey && self.consumesKey ? nil : event
        }
        monitors = [NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp], handler: handler)].compactMap { $0 }
        resign = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                        object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rehearsal.reset() }
        }
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        if let resign { NotificationCenter.default.removeObserver(resign) }
        resign = nil
        rehearsal.reset()
    }
}

/// macOS can claim the fn (🌐) key for emoji, input sources or its own dictation.
enum FnKeyUsage {
    static func conflicts(with hotkey: Hotkey) -> Bool {
        let usesFn = hotkey.modifiers & Hotkey.maskSecondaryFn != 0 || (hotkey.isModifierOnly && hotkey.keyCode == 63)
        guard usesFn else { return false }
        // 0 is Do Nothing. A missing value means the system default, which acts on fn.
        let usage = UserDefaults(suiteName: "com.apple.HIToolbox")?.object(forKey: "AppleFnUsageType") as? Int
        return usage != 0
    }

    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
    }
}

// MARK: Try It

struct OnboardingPracticeStep: View {
    @Environment(AppContainer.self) private var container
    let speech: OnboardingSpeechChoice
    let changeStep: (OnboardingProgress.Step) -> Void
    @State private var practiceText = ""
    @State private var monitor = HotkeyRehearsalMonitor()
    @FocusState private var focused: Bool

    private var progress: OnboardingProgress { container.settings.onboarding }
    private var busy: Bool { container.pipeline.isBusy }
    private var verb: String {
        container.settings.hotkeyBehavior.instructionVerb(triggerDelayMilliseconds: container.settings.triggerDelayMilliseconds)
    }
    private var chosen: ASRConfig { progress.chosenSpeech ?? container.settings.asr }
    private var pendingDownload: ModelDownloadStore.Job? {
        guard chosen.kind.isLocal, !LocalModels.isInstalled(chosen) else { return nil }
        return container.downloads.jobs[chosen.engineID]
    }
    private static var sentence: String {
        String(localized: "Hello! I’m trying Airdraft for the first time, and it’s writing what I say.")
    }

    var body: some View {
        if !container.license.access.allowsUse {
            SettingsCard {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Start your free trial to try dictation").font(.system(size: 13, weight: .medium))
                        Text("All features are included. Or activate a license you already have.").supportingText()
                    }
                    Spacer()
                    Button("Trial & License…") { container.showLicense() }.primaryButtonStyle()
                }
            }
        }

        Card(padding: 20, spacing: 10) {
            Text(progress.practiceDeliveries == 0 ? "READ THIS ALOUD" : "NOW SAY ANYTHING")
                .font(.system(size: 10, weight: .semibold)).tracking(0.8)
                .foregroundStyle(.secondary)
            Text(progress.practiceDeliveries == 0 ? "“\(Self.sentence)”"
                 : "Try a message you might send today. Speak naturally, with pauses if you like.")
                .font(.system(size: progress.practiceDeliveries == 0 ? 19 : 15, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboarding.script")
            HStack(spacing: 10) {
                Text(verb).font(.system(size: 13))
                OnboardingKeyCaps(hotkey: container.settings.hotkey, lit: monitor.rehearsal.litCaps, size: 28)
                Text(container.settings.hotkeyBehavior == .hold ? "and speak. Let go to insert." : "and speak. Press again to insert.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }

        practiceBox

        if progress.deliveredDuringPractice {
            Label(progress.practiceDeliveries == 1
                  ? "It worked. The small window at the bottom of your screen shows when Airdraft is listening."
                  : "Nice. Continue when you’re ready, or keep practicing.",
                  systemImage: "checkmark.circle.fill")
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboarding.practice-success")
        } else {
            Text("This is a real dictation with your chosen model. It also appears in History.").supportingText()
        }

        status
        DictationRecovery()
        if let issue = container.pipeline.lastIssue {
            Text(issue).supportingText().textSelection(.enabled)
        }
    }

    private var practiceBox: some View {
        TextEditor(text: $practiceText)
            .font(.system(size: 16))
            .scrollContentBackground(.hidden)
            .padding(Theme.cardPadding)
            .frame(minHeight: 130, idealHeight: 150)
            .background { SoftRaisedSurface(shape: SoftControl.shape, elevation: .card) }
            .overlay {
                SoftControl.shape
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    .opacity(focused ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                if practiceText.isEmpty {
                    Text(pendingDownload?.progress != nil ? "Almost ready. Your model is still downloading."
                         : focused ? "Now \(verb.lowercased()) your shortcut and speak." : "Click here first.")
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                        .padding(22).allowsHitTesting(false)
                }
            }
            .focused($focused)
            .accessibilityLabel("Practice dictation")
            .accessibilityIdentifier("onboarding.practice")
            .onAppear {
                focused = true
                monitor.start(container, consumesKey: false)
            }
            .onDisappear { monitor.stop() }
            .onChange(of: container.settings.hotkey) { _, _ in monitor.start(container, consumesKey: false) }
    }

    @ViewBuilder private var status: some View {
        if let issue = languageIssue {
            NoticeRow(issue) {
                Button("Change Language") { changeStep(.speech) }
                    .disabled(busy)
                    .accessibilityIdentifier("onboarding.change-language")
            }
        } else if let job = pendingDownload {
            if let current = job.progress {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Downloading \(speech.entry.title). Dictation starts working when it finishes.").supportingText()
                    ModelDownloadProgress(progress: current)
                }
                .accessibilityIdentifier("onboarding.practice-download")
            } else if let error = job.error {
                NoticeRow(error) {
                    Button("Retry Download") { retryDownload() }.disabled(busy)
                }
            }
        } else if chosen.kind.isLocal && !LocalModels.isInstalled(chosen) {
            NoticeRow("The speech model isn’t downloaded yet.") {
                Button("Download") { retryDownload() }.disabled(busy)
            }
        } else if container.speechConfig.kind.isLocal {
            modelReadiness
        }
    }

    private func retryDownload() {
        container.downloads.start(chosen) { [weak container] in container?.applyOnboardingSpeechIfReady() }
    }

    @ViewBuilder private var modelReadiness: some View {
        let state = container.engineStatus.state(for: container.speechConfig.engineID)
        HStack {
            switch state {
            case .ready: Label("Model is ready", systemImage: "checkmark.circle").supportingText()
            case .loading:
                ProgressView().controlSize(.small)
                Text("Loading the speech model…").supportingText()
            case .failed(let message): Text(message).supportingText().textSelection(.enabled)
            case .notLoaded: Text("Load the speech model to start speaking.").supportingText()
            }
            Spacer()
            if state != .ready && state != .loading {
                Button(state == .notLoaded ? "Load Model" : "Retry Loading") { container.models.loadSpeechModel() }
                    .buttonStyle(SoftButtonStyle()).disabled(busy)
            }
        }
        .accessibilityIdentifier("onboarding.model-readiness")
    }

    private var languageIssue: String? {
        do { _ = try SpeechLanguagePolicy.resolve(container.speechConfig); return nil }
        catch { return error.localizedDescription }
    }
}

// MARK: Ready

struct OnboardingDoneStep: View {
    @Environment(AppContainer.self) private var container
    let finish: () -> Void

    var body: some View {
        let settings = container.settings
        Card(padding: 20, spacing: 14) {
            Text("TRY IT IN A REAL APP")
                .font(.system(size: 10, weight: .semibold)).tracking(0.8)
                .foregroundStyle(.secondary)
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Open Notes, Mail or a chat, click where you would type, and use your shortcut.")
                        .font(.system(size: 15, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(settings.hotkeyBehavior == .hold ? "Hold while you speak, then let go." : "Press to start, press again when you finish.")
                        .supportingText()
                }
                Spacer(minLength: 8)
                OnboardingKeyCaps(hotkey: settings.hotkey, size: 40)
            }
        }

        OnboardingRefinementChoice(finish: finish)

        SettingsCard {
            tipLabel("menubar.rectangle", "Airdraft lives in the menu bar",
                "Open History, Settings or switch microphones from the icon at the top of your screen.")
            RowDivider()
            tipLabel("clock.arrow.circlepath", "Every dictation is kept in History",
                "If an app missed your words, copy them again from History.")
            RowDivider()
            tipLabel("escape", "Changed your mind?", "Press esc while recording and nothing is typed.")
        }
    }

    private func tipLabel(_ symbol: String, _ title: LocalizedStringResource, _ detail: LocalizedStringResource) -> some View {
        HStack(spacing: Theme.controlSpacing) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background { NeumorphicSurface(shape: RoundedRectangle(cornerRadius: 8, style: .continuous), inset: true, depth: 1.5) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).supportingText().fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Setup's refinement choice, offered after practice so the user has just seen the raw
/// transcript. On-device Apple Intelligence is one click; nothing here asks for a key,
/// a download or a prompt. Every other provider stays in Models.
struct OnboardingRefinementChoice: View {
    @Environment(AppContainer.self) private var container
    let finish: () -> Void
    @State private var availability = AppleIntelligenceSetup.availability

    private var llm: LLMConfig { container.settings.llm }
    private var available: Bool { availability == .available }

    var body: some View {
        SettingsCard {
            HStack(spacing: Theme.controlSpacing) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background { NeumorphicSurface(shape: RoundedRectangle(cornerRadius: 8, style: .continuous), inset: true, depth: 1.5) }
                VStack(alignment: .leading, spacing: 2) {
                    title.font(.system(size: 13, weight: .medium))
                    detail.supportingText().fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("onboarding.refinement")
                Spacer(minLength: Theme.controlSpacing)
                action
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Someone who turns Apple Intelligence on in System Settings comes back to the choice.
            availability = AppleIntelligenceSetup.availability
        }
    }

    private var title: Text {
        switch llm.kind {
        case .none: available ? Text("Tidy your words with Apple Intelligence") : Text("Let AI tidy your words")
        case .appleIntelligence: Text("Apple Intelligence tidies your words")
        default: Text("Your words are tidied by \(llm.displayName)")
        }
    }

    private var detail: Text {
        switch llm.kind {
        case .none:
            available ? Text("Removes filler words and fixes punctuation. It runs on this Mac, with no key or download.")
                : AppleIntelligenceSetup.explanation(availability)
        case .appleIntelligence:
            available ? Text("On this Mac. You can change or turn this off in Models.")
                : AppleIntelligenceSetup.explanation(availability)
        default: Text("You can change this in Models.")
        }
    }

    @ViewBuilder private var action: some View {
        switch llm.kind {
        case .none where available:
            Button("Use Apple Intelligence") { container.settings.chooseRefinement(.appleIntelligence) }
                .buttonStyle(SoftButtonStyle())
                .accessibilityIdentifier("onboarding.use-apple-intelligence")
        case .appleIntelligence:
            Button("Turn Off") { container.settings.chooseRefinement(.none) }
                .buttonStyle(SoftButtonStyle())
                .accessibilityIdentifier("onboarding.refinement-off")
        default:
            Button("Open Models") {
                finish()
                container.navigation.page = .models
            }
            .buttonStyle(SoftButtonStyle())
            .accessibilityIdentifier("onboarding.refinement-models")
        }
    }
}

/// Apple Intelligence availability for setup, from the same system check refinement
/// uses. Renders and fixtures inject it with `AIRDRAFT_RENDER_APPLE_INTELLIGENCE`.
enum AppleIntelligenceSetup {
    static var availability: AppleIntelligenceRefiner.Availability {
        RenderMode.value("APPLE_INTELLIGENCE").flatMap(AppleIntelligenceRefiner.Availability.init(rawValue:))
            ?? AppleIntelligenceRefiner.availability
    }

    static func explanation(_ availability: AppleIntelligenceRefiner.Availability) -> Text {
        switch availability {
        case .available: Text("Apple Intelligence is ready on this Mac.")
        case .requiresNewerSystem: Text("Apple Intelligence needs macOS 26 or later. You can set up another way to tidy your words in Models.")
        case .deviceNotEligible: Text("This Mac can’t run Apple Intelligence. You can set up another way to tidy your words in Models.")
        case .notEnabled: Text("Turn on Apple Intelligence in System Settings, then come back here. Or set it up later in Models.")
        case .modelNotReady: Text("Apple Intelligence is still getting ready on this Mac. Try again soon, or set it up later in Models.")
        case .unavailable: Text("Apple Intelligence isn’t available right now. You can set up a way to tidy your words later in Models.")
        }
    }
}
