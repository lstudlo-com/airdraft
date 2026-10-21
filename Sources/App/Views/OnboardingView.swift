import AirdraftCore
import AppKit
import SwiftUI

/// Six short steps that teach dictation by doing it, using the same permissions,
/// downloads, shortcut and pipeline as the rest of the app. Every step can be left
/// with Set Up Later; only a real dictation in Try It records success.
struct OnboardingView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var speech = OnboardingSpeechChoice()
    @State private var initialized = false
    @State private var shortcutPracticed = false

    private var progress: OnboardingProgress { container.settings.onboarding }
    private var step: OnboardingProgress.Step { progress.step }
    private var busy: Bool { container.pipeline.isBusy }
    private static let shadowRoom: CGFloat = 12

    var body: some View {
        HStack(spacing: 0) {
            OnboardingRail(speech: speech, go: changeStep)
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, Theme.pageHeaderTopInset)
                    .padding(.bottom, Theme.sectionSpacing - Self.shadowRoom)
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                        switch step {
                        case .welcome: OnboardingWelcomeStep()
                        case .speech: OnboardingSpeechStep(speech: speech)
                        case .permissions: OnboardingPermissionsStep()
                        case .shortcut: OnboardingShortcutStep(practiced: $shortcutPracticed)
                        case .practice: OnboardingPracticeStep(speech: speech, changeStep: changeStep)
                        case .done: OnboardingDoneStep(finish: finish)
                        }
                    }
                    .id(step)
                    .transition(.opacity)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Room for the cards' cast light and shade inside the scroll view,
                    // which would otherwise clip it; the outer inset keeps them aligned.
                    .padding(Self.shadowRoom)
                    .padding(.bottom, Theme.pagePadding - Self.shadowRoom)
                }
                .padding(.horizontal, -Self.shadowRoom)
                footer.padding(.vertical, Theme.pagePadding)
            }
            .padding(.horizontal, Theme.pagePadding)
            .contentIsland()
        }
        .background(SidebarBackground())
        .frame(width: Theme.windowWidth)
        .frame(minHeight: Theme.windowMinHeight, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear {
            initialize()
            updateDictationPause()
        }
        .onDisappear {
            container.hotkeys.rehearsing = false
            container.settings.endOnboardingPractice()
        }
        .task(id: speech.config.keyRef) { await speech.refreshKey() }
        .onReceive(NotificationCenter.default.publisher(for: Keychain.didChange).receive(on: DispatchQueue.main)) { _ in
            Task { await speech.refreshKey() }
        }
        .onChange(of: container.downloads.jobs) { _, _ in
            speech.refreshInstalled()
            container.applyOnboardingSpeechIfReady()
            updateDictationPause()
        }
        .onChange(of: step) { _, _ in updateDictationPause() }
        .onChange(of: container.settings.asr) { _, _ in updateDictationPause() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).appFont(.display).tracking(-0.5)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle).appFont(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: Theme.controlSpacing) {
            if let previous = step.previous, step != .done {
                Button("Back") { changeStep(previous) }
                    .buttonStyle(SoftButtonStyle()).disabled(busy)
                    .accessibilityIdentifier("onboarding.back")
            }
            Spacer()
            if step == .shortcut && !shortcutPracticed {
                Text("Try the keys first, or continue when you are ready.").supportingText()
            }
            Button(continueTitle, action: advance)
                .primaryButtonStyle()
                .keyboardShortcut(.defaultAction)
                .disabled(!canContinue || busy)
                .accessibilityIdentifier("onboarding.continue")
        }
    }

    private var continueTitle: String {
        switch step {
        case .welcome: String(localized: "Get Started")
        case .speech: speech.isDownloading ? String(localized: "Continue While It Downloads") : String(localized: "Continue")
        case .done: String(localized: "Start Using Airdraft")
        default: String(localized: "Continue")
        }
    }

    private var canContinue: Bool {
        switch step {
        case .welcome, .shortcut, .done: true
        case .speech: speech.canContinue
        case .permissions:
            OnboardingPermissionsStep.microphoneGranted(container) && OnboardingPermissionsStep.accessibilityGranted(container)
        case .practice: progress.deliveredDuringPractice
        }
    }

    private func advance() {
        switch step {
        case .speech:
            let config = speech.config
            if !config.kind.isLocal || speech.localInstalled {
                container.settings.asr = config
            } else if container.downloads.jobs[config.engineID]?.progress == nil {
                container.downloads.start(config) { [weak container] in container?.applyOnboardingSpeechIfReady() }
            }
            progress.chooseSpeech(config)
            changeStep(.permissions)
        case .practice:
            container.settings.endOnboardingPractice()
            animate { _ = progress.complete() }
        case .done: finish()
        default:
            if let next = step.next { changeStep(next) }
        }
    }

    private func finish() {
        progress.finish()
        container.navigation.page = .home
    }

    private func initialize() {
        guard !initialized else { return }
        initialized = true
        speech.configure(container)
        if step == .practice { container.settings.beginOnboardingPractice() }
        container.applyOnboardingSpeechIfReady()
        if !RenderMode.isActive {
            container.permissions.refresh()
            container.microphones.refresh()
        }
    }

    /// Dictation pauses while practicing the keys, and in Try It until the chosen model
    /// has finished downloading, so a press can never start the wrong engine.
    private func updateDictationPause() {
        guard !RenderMode.isActive else { return }
        container.hotkeys.rehearsing = step.pausesDictation(speechReady: container.onboardingSpeechReady)
    }

    func changeStep(_ next: OnboardingProgress.Step) {
        guard next != step else { return }
        if step == .practice { container.settings.endOnboardingPractice() }
        if next == .practice {
            container.settings.beginOnboardingPractice()
            // Renders and fixtures never load a model; their files are presence markers.
            if container.onboardingSpeechReady && !RenderMode.isActive { container.models.loadSpeechModel() }
        }
        animate { progress.move(to: next) }
    }

    private func animate(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { change() }
    }

    private var title: String {
        switch step {
        case .welcome: String(localized: "Talk, and your words appear where you type.")
        case .speech: String(localized: "Choose how Airdraft listens.")
        case .permissions: String(localized: "Let Airdraft hear you and type for you.")
        case .shortcut: String(localized: "Meet your shortcut.")
        case .practice: String(localized: "Say your first sentence.")
        case .done: String(localized: "You’re ready to dictate.")
        }
    }

    private var subtitle: String {
        let verb = container.settings.hotkeyBehavior.instructionVerb(
            triggerDelayMilliseconds: container.settings.triggerDelayMilliseconds).lowercased()
        switch step {
        case .welcome:
            return String(localized: "Airdraft turns speech into text in any app: email, chat, notes and documents. Setup takes about three minutes, and you can stop at any time.")
        case .speech:
            return String(localized: "Pick where your speech becomes text. You can change this later in Models.")
        case .permissions:
            return String(localized: "macOS asks once. Airdraft only records while you use your shortcut.")
        case .shortcut:
            return String(localized: "One shortcut starts dictation in every app. Practice it here; nothing is recorded on this step.")
        case .practice:
            return progress.deliveredDuringPractice
                ? String(localized: "That was a real dictation. Try one more in your own words, or continue.")
                : String(localized: "Click in the box below, \(verb) your shortcut and read the sentence aloud.")
        case .done:
            return String(localized: "Airdraft works anywhere you can type. Here is how to make it part of your day.")
        }
    }
}

/// The speech engine chosen during setup. A local model may still be downloading
/// while the remaining steps continue.
@MainActor @Observable
final class OnboardingSpeechChoice {
    var useCloud = false
    var localChoice = "sherpa:senseVoice"
    var cloudChoice: ASRProviderKind = .groq
    private(set) var recommendation = ModelCatalogue.recommendation
    var recommendedID: String { recommendation.model.catalogueID }
    private(set) var localInstalled = false
    private(set) var keyPresent = false
    @ObservationIgnored private weak var container: AppContainer?

    var entry: ModelEntry {
        ModelCatalogue.entries.first { $0.id == localChoice }
            ?? ModelCatalogue.entry(recommendation.model)
    }
    /// The recommendation and its alternatives, best first, plus a model chosen
    /// elsewhere (an existing install or the picker) so the selection stays visible.
    var options: [ModelEntry] {
        let suggested = ([recommendation.model] + recommendation.alternatives).map(ModelCatalogue.entry)
        return suggested.contains { $0.id == entry.id } ? suggested : [entry] + suggested
    }
    var preset: EndpointPreset.Speech { EndpointPreset.asr.first { $0.kind == cloudChoice }! }
    private var base: ASRConfig { container?.settings.asr ?? ASRConfig() }
    var localConfig: ASRConfig { entry.config(from: base) }
    var config: ASRConfig {
        if !useCloud { return localConfig }
        var config = base
        config.select(cloudChoice)
        return config
    }
    var download: ModelDownloadStore.Job? { container?.downloads.jobs[localConfig.engineID] }
    var isDownloading: Bool { !useCloud && !localInstalled && download?.progress != nil }
    var languageIssue: String? {
        do { _ = try SpeechLanguagePolicy.resolve(config); return nil }
        catch { return error.localizedDescription }
    }
    var canContinue: Bool {
        languageIssue == nil && (useCloud ? keyPresent : localInstalled || isDownloading)
    }

    func configure(_ container: AppContainer) {
        self.container = container
        let current = container.settings.onboarding.chosenSpeech ?? container.settings.asr
        recommendation = ModelCatalogue.recommendation
        useCloud = !current.kind.isLocal && current.kind.preset != nil
        cloudChoice = current.kind.preset?.kind ?? .groq
        let keepCurrent = container.settings.onboarding.chosenSpeech != nil || container.settings.hadExistingSetup
            || container.settings.onboarding.step == .practice || LocalModels.isInstalled(current)
        localChoice = ModelCatalogue.entries.first {
            $0.isDownloadable && $0.isSelected(current) && keepCurrent
        }?.id ?? recommendedID
        refreshInstalled()
    }

    func refreshInstalled() { localInstalled = LocalModels.isInstalled(localConfig) }

    func refreshKey() async {
        guard !RenderMode.isActive, !RenderMode.excludesCredentials else { return }
        let account = config.keyRef
        let present = await Task.detached { Keychain.presence(account) == .saved }.value
        guard account == config.keyRef else { return }
        keyPresent = present
    }
}

extension AppContainer {
    /// Onboarding's speech choice becomes the app default once it can be used. A choice
    /// left behind by Set Up Later never overrides a later selection in Models.
    func applyOnboardingSpeechIfReady() {
        let progress = settings.onboarding
        guard progress.isPresented, let chosen = progress.chosenSpeech,
              !chosen.kind.isLocal || LocalModels.isInstalled(chosen), settings.asr != chosen else { return }
        settings.asr = chosen
        if progress.step == .practice && !RenderMode.isActive { models.loadSpeechModel() }
    }

    /// Whether Try It can use the engine chosen in setup right now.
    var onboardingSpeechReady: Bool {
        let chosen = settings.onboarding.chosenSpeech ?? settings.asr
        return settings.asr == chosen && (!chosen.kind.isLocal || LocalModels.isInstalled(chosen))
    }
}

/// Steps on the sidebar's own selection well, so setup reads as part of the app.
private struct OnboardingRail: View {
    @Environment(AppContainer.self) private var container
    let speech: OnboardingSpeechChoice
    let go: (OnboardingProgress.Step) -> Void

    private var progress: OnboardingProgress { container.settings.onboarding }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarBrandMark()
                .padding(.horizontal, Theme.sidebarBrandInset)
                .padding(.top, 54)
                .padding(.bottom, 20)
            VStack(spacing: 2) {
                ForEach(OnboardingProgress.Step.allCases, id: \.self) { step in row(step) }
            }
            .sidebarSelectionWell(selection: progress.step)
            Spacer(minLength: 20)
            // Speech and Try It show the same progress in the page itself.
            if let job = speech.download, let current = job.progress, !speech.useCloud,
               ![.speech, .practice].contains(progress.step) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Downloading \(speech.entry.title)")
                        .appFont(.supporting, weight: .medium)
                        .lineLimit(1)
                    ModelDownloadProgress(progress: current)
                }
                .padding(.horizontal, NavigationStyle.destinationInset + 6)
                .padding(.bottom, 16)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("onboarding.rail-download")
            }
            Button("Set Up Later") { progress.dismiss() }
                .buttonStyle(.link).appFont(.detail)
                .disabled(container.pipeline.isBusy)
                .help("Your progress is saved. Reopen it from the Airdraft menu with Set Up Airdraft.")
                .padding(.horizontal, NavigationStyle.destinationInset + 6)
                .padding(.bottom, Theme.pagePadding)
                .opacity(progress.step == .done ? 0 : 1)
                .accessibilityHidden(true, isEnabled: progress.step == .done)
        }
        .padding(.horizontal, Theme.sidebarContentInset)
        .frame(width: Theme.sidebarWidth, alignment: .leading)
    }

    private func row(_ step: OnboardingProgress.Step) -> some View {
        let current = step == progress.step
        let passed = step.index < progress.step.index
        // Earlier steps can be revisited; later ones open through Continue.
        let reachable = passed && progress.step != .done
        return Button { if reachable { go(step) } } label: {
            HStack(spacing: NavigationStyle.labelStart - NavigationStyle.iconIslandInset - NavigationStyle.iconIslandSize) {
                SidebarIcon(symbol: passed ? "checkmark" : step.symbol, selected: current)
                    .frame(width: NavigationStyle.iconIslandSize)
                    .sidebarSelectionIconAnchor(step)
                Text(step.title)
                    .appFont(.body)
                    .foregroundStyle(current || passed ? .primary : .secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, NavigationStyle.iconIslandInset)
            .padding(.trailing, 6)
            .frame(height: NavigationStyle.destinationHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(NavigationRowStyle(selected: current, slidingSelection: true))
        .allowsHitTesting(reachable && !container.pipeline.isBusy)
        .sidebarSelectionAnchor(step)
        .padding(.horizontal, NavigationStyle.destinationInset)
        .accessibilityLabel("Step \(step.index + 1) of \(OnboardingProgress.Step.allCases.count): \(step.title)")
        .accessibilityValue(passed ? Text("Done") : current ? Text("Current") : Text(verbatim: ""))
        .accessibilityAddTraits(current ? .isSelected : [])
    }
}

extension OnboardingProgress.Step {
    var title: String {
        switch self {
        case .welcome: String(localized: "Welcome")
        case .speech: String(localized: "Speech")
        case .permissions: String(localized: "Permissions")
        case .shortcut: String(localized: "Shortcut")
        case .practice: String(localized: "Try It")
        case .done: String(localized: "Ready")
        }
    }

    var symbol: String {
        switch self {
        case .welcome: "hand.wave"
        case .speech: "waveform"
        case .permissions: "lock.open"
        case .shortcut: "command"
        case .practice: "text.cursor"
        case .done: "flag.checkered"
        }
    }
}
