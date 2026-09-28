import AirdraftCore
import AppKit
import AVFoundation
import SwiftUI

/// Three real setup tasks, using the same permissions, downloads and dictation
/// pipeline as the rest of the app. No second recording or credential stack.
struct OnboardingView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var practiceText = ""
    @State private var localChoice = "sherpa:senseVoice"
    @State private var cloudChoice: ASRProviderKind = .groq
    @State private var useCloud = false
    @State private var initialized = false
    @State private var speechKeyPresent = false
    @State private var localInstalled = false
    @FocusState private var practiceFocused: Bool

    private var progress: OnboardingProgress { container.settings.onboarding }
    private var busy: Bool { container.pipeline.isBusy }
    private var entry: ModelEntry {
        ModelCatalogue.entries.first { $0.id == localChoice } ?? ModelCatalogue.entries[4]
    }
    private var localConfig: ASRConfig { entry.config(from: container.settings.asr) }
    private var speechConfig: ASRConfig {
        if !useCloud { return localConfig }
        var config = container.settings.asr
        config.select(cloudChoice)
        return config
    }
    private var preset: EndpointPreset.Speech { EndpointPreset.asr.first { $0.kind == cloudChoice }! }
    private var download: ModelDownloadStore.Job? { container.downloads.jobs[localConfig.engineID] }
    private var canContinue: Bool {
        switch progress.step {
        case .permissions:
            return container.permissions.microphone == .authorized && container.permissions.accessibilityGranted
        case .speech: return useCloud ? speechKeyPresent : localInstalled
        case .practice: return progress.deliveredDuringPractice
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            rail
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, Theme.titlebarHeight + Theme.pageHeaderTopInset)
                    .padding(.bottom, Theme.sectionSpacing)
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                        switch progress.step {
                        case .permissions: permissions
                        case .speech: speech
                        case .practice: practice
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, Theme.pagePadding)
                }
                footer.padding(.vertical, Theme.pagePadding)
            }
            .padding(.horizontal, Theme.pagePadding)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: Theme.windowWidth)
        .frame(minHeight: Theme.windowMinHeight, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear { initialize() }
        .onDisappear { container.settings.endOnboardingPractice() }
        .task(id: speechConfig.keyRef) { await refreshKey() }
        .onChange(of: localChoice) { _, _ in refreshInstalled() }
        .onChange(of: download) { _, _ in refreshInstalled() }
        .onReceive(NotificationCenter.default.publisher(for: Keychain.didChange).receive(on: DispatchQueue.main)) { _ in
            Task { await refreshKey() }
        }
        .onChange(of: progress.step) { _, step in practiceFocused = step == .practice }
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarBrandMark()
                .padding(.horizontal, Theme.sidebarBrandInset)
                .padding(.top, 54)
                .padding(.bottom, 36)
            ForEach(OnboardingProgress.Step.allCases, id: \.rawValue) { step in
                let current = step == progress.step
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(current ? Color.accentColor : Color.primary.opacity(0.06))
                        if step.rawValue < progress.step.rawValue {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                        } else {
                            Text("\(step.rawValue + 1)").font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .foregroundStyle(current ? Color.white : Color.secondary)
                    .frame(width: 24, height: 24)
                    Text(stepLabel(step)).font(.system(size: 13, weight: current ? .semibold : .regular))
                        .foregroundStyle(current ? .primary : .secondary)
                }
                .padding(.horizontal, Theme.sidebarContentInset)
                .padding(.vertical, 12)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(step.rawValue + 1) of 3: \(stepLabel(step))")
                .accessibilityAddTraits(current ? .isSelected : [])
            }
            Spacer()
            Button("Set Up Later") { progress.dismiss() }
                .buttonStyle(.link).font(.system(size: 12))
                .disabled(busy)
                .help("Your progress is saved. Reopen from the Airdraft menu.")
                .padding(.horizontal, Theme.sidebarContentInset)
                .padding(.bottom, Theme.pagePadding)
        }
        .padding(.horizontal, Theme.sidebarContentInset)
        .frame(width: Theme.sidebarWidth, alignment: .leading)
        .background(SidebarBackground())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 25, weight: .semibold)).tracking(-0.5)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            SettingsCard {
                permissionRow("Microphone", detail: "Record while you dictate.", ready: container.permissions.microphone == .authorized) {
                    Button(container.permissions.microphone == .notDetermined ? "Allow Microphone" : "Open Settings") {
                        if container.permissions.microphone == .notDetermined {
                            Task { await container.permissions.requestMicrophone() }
                        } else {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                        }
                    }.buttonStyle(SoftButtonStyle())
                }
                RowDivider()
                permissionRow("Accessibility", detail: "Insert your words into other apps.", ready: container.permissions.accessibilityGranted) {
                    Button("Open Settings") { container.openAccessibilitySettings() }.buttonStyle(SoftButtonStyle())
                }
            }
            PageSection("Your microphone") {
                SettingsCard {
                    SettingRow(title: "Input") {
                        Picker("Microphone", selection: Binding(
                            get: { container.settings.microphone.uid ?? "" },
                            set: { uid in
                                let device = container.microphones.devices.first { $0.uid == uid }
                                let choice = device.map { MicrophonePreference(uid: $0.uid, name: $0.name) } ?? .systemDefault
                                container.settings.microphone = container.microphones.selection(choice, preservingChannelFrom: container.settings.microphone)
                            }
                        )) {
                            Text("System Default").tag("")
                            ForEach(container.microphones.devices) { Text($0.name).tag($0.uid) }
                        }.settingsPicker(width: 240)
                    }
                }
            }
            HStack {
                Text("Already allowed access?").supportingText()
                Button("Check Again") { container.permissions.refresh(); container.microphones.refresh() }
                    .buttonStyle(.link).font(.system(size: 12))
                Spacer()
                AccessibilityPermissionActions()
            }
        }
    }

    private var speech: some View {
        VStack(alignment: .leading, spacing: Theme.sectionTitleSpacing) {
            Picker("Speech processing", selection: $useCloud) {
                Text("On This Mac").tag(false)
                Text("My API Key").tag(true)
            }.pickerStyle(.segmented).disabled(busy)
            Text(useCloud ? "Audio goes to your chosen provider. Its usage charges are separate from Airdraft."
                 : "Speech is processed on this Mac. Download a model once to use it offline.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Theme.sectionTitleSpacing)
            if useCloud {
                SettingsCard {
                    SettingRow(title: "Provider") {
                        Picker("Provider", selection: $cloudChoice) {
                            ForEach(EndpointPreset.asr) { Text($0.name).tag($0.kind) }
                        }.settingsPicker(width: 180)
                    }
                    RowDivider()
                    SpeechKeyRows(preset: preset, config: speechConfig)
                }
                Text("The first dictation will confirm transcription access and billing.").supportingText()
            } else {
                localModel
            }
            Text(container.settings.hadExistingSetup
                 ? "Practice uses direct transcription and inserts at the cursor. Your refinement and output settings return when you leave."
                 : "Start with direct transcription. Add AI text refinement in Models later.")
                .supportingText().fixedSize(horizontal: false, vertical: true)
        }
    }

    private var localModel: some View {
        SettingsCard {
            SettingRow(title: "Speech model") {
                Picker("Speech model", selection: $localChoice) {
                    ForEach(ModelCatalogue.entries.filter { $0.isDownloadable }) { Text($0.title).tag($0.id) }
                }.settingsPicker(width: 225)
            }
            RowDivider()
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.tags.joined(separator: " · ")).font(.system(size: 12, weight: .medium))
                    if case .download(let size) = entry.storage {
                        Text("Download estimate: \(size). Installed size and memory use differ.").supportingText()
                    }
                }
                Spacer()
                if localInstalled {
                    Label("Downloaded", systemImage: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(.secondary)
                } else if download?.progress != nil {
                    Button("Cancel") { container.downloads.cancel(localConfig) }.buttonStyle(SoftButtonStyle())
                } else {
                    Button(download?.error == nil ? "Download Model" : "Retry Download") {
                        container.downloads.start(localConfig)
                    }.buttonStyle(SoftButtonStyle())
                }
            }
            if let current = download?.progress {
                ProgressView(value: current.fraction)
                    .accessibilityLabel("Model download")
                Text(current.currentFile).supportingText().lineLimit(2)
            }
            if let error = download?.error { Text(error).supportingText().textSelection(.enabled) }
        }
    }

    private var practice: some View {
        VStack(alignment: .leading, spacing: Theme.sectionTitleSpacing) {
            HStack(spacing: 10) {
                Text(container.settings.hotkeyBehavior.instructionVerb).font(.system(size: 13))
                KeyCaps(hotkey: container.settings.hotkey)
                Text(container.settings.hotkeyBehavior == .hold ? "and speak. Release to insert." : "and speak. Press again to insert.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            TextEditor(text: $practiceText)
                .font(.system(size: 16))
                .scrollContentBackground(.hidden)
                .padding(Theme.cardPadding)
                .frame(minHeight: 160, idealHeight: 180)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cardRadius)
                        .strokeBorder(practiceFocused ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: practiceFocused ? 1.5 : 0.5)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .topLeading) {
                    if practiceText.isEmpty {
                        Text("Click here, then try: Let’s get started.")
                            .font(.system(size: 14)).foregroundStyle(.secondary)
                            .padding(22).allowsHitTesting(false)
                    }
                }
                .focused($practiceFocused)
                .accessibilityLabel("Try your first dictation")
                .accessibilityIdentifier("onboarding.practice")
            if progress.deliveredDuringPractice {
                Label("Your first dictation is ready.", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            } else {
                Text("This uses your real model and settings. Your result also appears in History.").supportingText()
            }
            if container.settings.asr.kind.isLocal {
                HStack {
                    Text(container.engineStatus.state(for: container.settings.asr.engineID) == .ready ? "Model is ready" : "Wait for the model to load before speaking.")
                        .supportingText()
                    Spacer()
                    Button("Load Model") { container.models.loadSpeechModel() }
                        .buttonStyle(SoftButtonStyle())
                        .disabled(busy || container.engineStatus.state(for: container.settings.asr.engineID) == .loading)
                }
            }
            DictationRecovery()
            if let issue = container.pipeline.lastIssue {
                Text(issue).supportingText().textSelection(.enabled)
            }
        }
    }

    private var footer: some View {
        HStack {
            if progress.step != .permissions {
                Button("Back") {
                    changeStep(OnboardingProgress.Step(rawValue: progress.step.rawValue - 1)!)
                }.buttonStyle(SoftButtonStyle()).disabled(busy)
            }
            Spacer()
            Button(progress.step == .practice ? "Start Using Airdraft" : progress.step == .speech ? "Use This Setup" : "Continue") {
                switch progress.step {
                case .permissions: changeStep(.speech)
                case .speech:
                    container.settings.asr = speechConfig
                    container.settings.beginOnboardingPractice()
                    container.models.loadSpeechModel()
                    changeStep(.practice)
                case .practice: progress.complete()
                }
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!canContinue || busy)
        }
    }

    private func permissionRow<Actions: View>(_ title: String, detail: String, ready: Bool,
                                               @ViewBuilder actions: () -> Actions) -> some View {
        HStack(spacing: Theme.controlSpacing) {
            StatusDot(ok: ready)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(ready ? "Allowed" : detail).supportingText()
            }
            Spacer()
            if !ready { actions() }
        }
    }

    private func initialize() {
        guard !initialized else { return }
        initialized = true
        useCloud = !container.settings.asr.kind.isLocal && container.settings.asr.kind.preset != nil
        cloudChoice = container.settings.asr.kind.preset?.kind ?? .groq
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let recommendation = ["zh", "en", "ja", "ko"].contains(language) ? "sherpa:senseVoice" : "whisper:turbo"
        localChoice = ModelCatalogue.entries.first { $0.isSelected(container.settings.asr) && LocalModels.isInstalled(container.settings.asr) }?.id ?? recommendation
        refreshInstalled()
        if progress.step == .practice { container.settings.beginOnboardingPractice() }
        if !RenderMode.isActive {
            container.permissions.refresh()
            container.microphones.refresh()
        }
    }

    private func refreshInstalled() { localInstalled = LocalModels.isInstalled(localConfig) }

    private func refreshKey() async {
        guard !RenderMode.isActive, !RenderMode.excludesCredentials else { return }
        let account = speechConfig.keyRef
        let present = await Task.detached { Keychain.presence(account) == .saved }.value
        guard account == speechConfig.keyRef else { return }
        speechKeyPresent = present
    }

    private func changeStep(_ step: OnboardingProgress.Step) {
        if progress.step == .practice && step != .practice { container.settings.endOnboardingPractice() }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { progress.move(to: step) }
    }

    private func stepLabel(_ step: OnboardingProgress.Step) -> String {
        switch step { case .permissions: "Permissions"; case .speech: "Speech"; case .practice: "Try It" }
    }
    private var title: String {
        switch progress.step {
        case .permissions: "A little setup. Then just speak."
        case .speech: "Choose where your voice goes."
        case .practice: "Your first words, in place."
        }
    }
    private var subtitle: String {
        switch progress.step {
        case .permissions: "Two permissions let Airdraft hear you and put your words where you need them."
        case .speech: "Use a model on this Mac, or connect your own cloud provider."
        case .practice: "Click the space below and use your shortcut. The same gesture works in your other apps."
        }
    }
}
