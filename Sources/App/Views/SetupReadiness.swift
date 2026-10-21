import AirdraftCore
import AppKit
import SwiftUI

/// Whether the current speech and refinement keys are saved. Home and the sidebar
/// read the same values, so they never disagree about setup.
@MainActor @Observable
final class SetupCredentialPresence {
    private(set) var speechKeyPresent = false
    private(set) var refinementKeyPresent = false

    /// Presence only: never reads a key value or prompts.
    func refresh(_ container: AppContainer) async {
        guard !RenderMode.isActive, !RenderMode.excludesCredentials else { return }
        let speech = container.speechConfig.keyRef
        let refinement = container.settings.llm.keyRef
        let present = await Task.detached {
            (Keychain.presence(speech) == .saved, Keychain.presence(refinement) == .saved)
        }.value
        guard !Task.isCancelled else { return }
        if container.speechConfig.keyRef == speech { speechKeyPresent = present.0 }
        if container.settings.llm.keyRef == refinement { refinementKeyPresent = present.1 }
    }
}

/// File-system and system-service facts behind readiness: whether the speech
/// model's files are installed, whether the output script is usable, whether
/// Apple Intelligence is available and whether the selected CLI exists. They are
/// measured off the main actor whenever their inputs change, after a download
/// finishes and when Airdraft becomes active, so Home and sidebar redraws never
/// stat files, search PATH or query the system language model.
@MainActor @Observable
final class SetupFacts {
    struct Inputs: Equatable, Sendable {
        var speech: ASRConfig
        /// Nil unless output goes to a script.
        var scriptPath: String?
        var llm: LLMConfig
    }

    struct Values: Equatable, Sendable {
        var speechInstalled = false
        var scriptIssue: String?
        var appleIntelligenceIssue: String?
        var cliMissing = false
    }

    private(set) var measured: (inputs: Inputs, values: Values)?
    @ObservationIgnored private var refreshID = UUID()
    @ObservationIgnored private var downloadSignature: [String: Bool] = [:]
    @ObservationIgnored private var activationObserver: NSObjectProtocol?

    /// The current values. Until the refresh for changed inputs lands (a few
    /// milliseconds), this measures directly without storing, so a redraw never
    /// shows facts about the previous model or script.
    func values(for inputs: Inputs) -> Values {
        if let measured, measured.inputs == inputs { return measured.values }
        return Self.measure(inputs)
    }

    /// Measures off the main actor; a newer refresh rejects an older result.
    func refresh(_ inputs: Inputs) async {
        let token = UUID()
        refreshID = token
        let values = await Task.detached(priority: .userInitiated) { Self.measure(inputs) }.value
        guard refreshID == token else { return }
        if measured?.inputs != inputs || measured?.values != values { measured = (inputs, values) }
    }

    nonisolated static func measure(_ inputs: Inputs) -> Values {
        var values = Values()
        values.speechInstalled = !inputs.speech.kind.isLocal || LocalModels.isInstalled(inputs.speech)
        values.scriptIssue = inputs.scriptPath.flatMap { ScriptDelivery.unavailableReason(path: $0) }
        if inputs.llm.kind == .appleIntelligence { values.appleIntelligenceIssue = AppleIntelligenceRefiner.unavailableReason }
        values.cliMissing = inputs.llm.kind.isCLI && inputs.llm.cliExecutable == nil
        return values
    }

    /// Starts refreshing for `container`. Called once from `AppContainer.start()`.
    func startRefreshing(_ container: AppContainer) {
        guard activationObserver == nil else { return }
        observeChanges({ [weak container] in
            guard let container else { return }
            _ = container.setupFactsInputs
            // Finished, failed or cancelled downloads change installed files.
            _ = container.downloads.jobs
        }) { [weak self, weak container] in
            guard let self, let container else { return }
            let signature = container.downloads.jobs.mapValues { $0.progress == nil }
            let inputs = container.setupFactsInputs
            guard measured?.inputs != inputs || signature != downloadSignature else { return }
            downloadSignature = signature
            Task { await self.refresh(inputs) }
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self, weak container] _ in
            // Files and system settings may have changed while Airdraft was inactive.
            MainActor.assumeIsolated {
                guard let self, let container else { return }
                Task { await self.refresh(container.setupFactsInputs) }
            }
        }
        Task { await refresh(container.setupFactsInputs) }
    }
}

extension AppContainer {
    var setupFactsInputs: SetupFacts.Inputs {
        SetupFacts.Inputs(speech: speechConfig,
                          scriptPath: settings.outputDestination == .script ? settings.outputScriptPath : nil,
                          llm: settings.llm)
    }
}

/// The one readiness model behind Home's setup card and hero and the sidebar
/// footer. Everything it reads is in memory: file and system checks come from
/// `SetupFacts`.
@MainActor
struct SetupReadiness {
    let container: AppContainer
    private var keys: SetupCredentialPresence { container.credentialPresence }
    private var facts: SetupFacts.Values { container.setupFacts.values(for: container.setupFactsInputs) }

    /// Setup rows plus the license and kept-recording bounds the pipeline enforces,
    /// so Home never says Ready while the shortcut would be refused.
    var issueCount: Int { setupIssueCount + blockers.count }

    var setupIssueCount: Int {
        [container.hotkeys.isActive, outputReady, microphoneReady, speechTone != .attention, refinementTone != .attention]
            .filter { !$0 }.count
    }

    var summary: String {
        let issues = issueCount
        if issues == 0 { return String(localized: "Ready to dictate") }
        if blockers.isEmpty {
            if issues == 1 { return String(localized: "1 setup step needs attention") }
            return String(localized: "\(issues) setup steps need attention")
        }
        if issues == 1, let blocker = blockers.first {
            switch blocker {
            case .license(.needsTrial): return String(localized: "Start your free trial to dictate")
            case .license: return String(localized: "A license is needed to dictate")
            case .waitingRecordings: return String(localized: "Recordings are waiting for retry")
            }
        }
        return String(localized: "\(issues) items need attention")
    }

    /// The sidebar footer names the kind of work Home is waiting on.
    var footerTitle: LocalizedStringResource {
        guard setupIssueCount == 0, blockers.count == 1, let blocker = blockers.first else { return "Finish Setup" }
        switch blocker {
        case .waitingRecordings: return "Recordings Waiting"
        case .license(.needsTrial): return "Start Trial"
        case .license: return "License"
        }
    }

    /// The license is the only issue, so the footer opens the License sheet
    /// instead of Home.
    var footerOpensLicense: Bool { setupIssueCount == 0 && blockers.count == 1 && licenseBlocker != nil }

    // MARK: Pipeline blockers

    var blockers: [DictationBlocker] {
        DictationBlocker.current(license: container.license.access, canKeepAnotherRecording: canKeepAnotherRecording)
    }

    var licenseBlocker: LicenseStore.Access? {
        for case .license(let access) in blockers { return access }
        return nil
    }

    var recordingsBlocked: Bool { blockers.contains(.waitingRecordings) }

    /// The pipeline's own bound. Debug renders fill it with `AIRDRAFT_RENDER_PENDING_RECORDINGS`.
    private var canKeepAnotherRecording: Bool {
        if let count = RenderMode.value("PENDING_RECORDINGS").flatMap(Int.init) {
            return count < DictationPipeline.maximumPendingRecordings
        }
        return container.pipeline.canKeepAnotherRecording
    }

    var licenseDetail: String {
        switch licenseBlocker {
        case .needsTrial: String(localized: "Start a free trial or enter a license key")
        case .expired: String(localized: "Your trial or license has ended")
        case .revoked: String(localized: "This license is no longer active")
        case .locked: String(localized: "License needs Keychain access")
        case .clockChanged: String(localized: "Correct the date and time to continue your trial")
        case .unconfigured: String(localized: "This build is missing its licensing configuration")
        default: ""
        }
    }

    var recordingsDetail: String {
        String(localized: "Retry or discard a waiting recording above to record again")
    }

    var outputReady: Bool {
        container.settings.outputDestination == .script
            ? facts.scriptIssue == nil
            : container.permissions.accessibilityGranted
    }

    /// Home's Script output row: the problem, or the script's file name.
    var scriptDetail: String {
        facts.scriptIssue ?? URL(fileURLWithPath: container.settings.outputScriptPath).lastPathComponent
    }

    /// The selected speech model's files are on disk, or it needs none.
    var speechInstalled: Bool { facts.speechInstalled }

    var microphoneReady: Bool {
        guard container.permissions.microphone == .authorized,
              let device = container.microphones.selected(container.settings.microphone) else { return false }
        let channel = container.settings.microphone.channelIndex ?? 0
        return channel >= 0 && channel < device.inputChannelCount
    }

    var microphoneDetail: String {
        if container.permissions.microphone != .authorized { return String(localized: "Microphone permission needed") }
        guard let device = container.microphones.selected(container.settings.microphone) else { return String(localized: "Selected microphone is unavailable") }
        return microphoneReady ? device.name : String(localized: "Selected input channel is unavailable")
    }

    var speechKeyPresent: Bool { keys.speechKeyPresent }

    var speechDetail: String {
        if let reason = container.effectiveProfile.speechModel?.unavailableReason { return reason }
        if let issue = speechLanguageIssue { return issue }
        let asr = container.speechConfig
        if !asr.kind.isLocal {
            guard asr.kind.preset != nil else { return String(localized: "Custom endpoint") }
            return speechKeyPresent ? String(localized: "API key saved") : String(localized: "API key missing or locked")
        }
        if !facts.speechInstalled { return String(localized: "Model not installed") }
        if speechLoadsOnDemand { return String(localized: "Loads when you dictate") }
        return container.engineStatus.state(for: asr.engineID).label
    }

    /// An installed local model that is not in memory is ready: starting
    /// dictation loads it. Only missing files, keys, bindings, languages or a
    /// failed load need attention.
    var speechTone: StatusDot.Tone {
        if container.effectiveProfile.speechModel?.unavailableReason != nil || speechLanguageIssue != nil { return .attention }
        let asr = container.speechConfig
        if !asr.kind.isLocal { return asr.kind.preset == nil || speechKeyPresent ? .ok : .attention }
        guard facts.speechInstalled else { return .attention }
        switch container.engineStatus.state(for: asr.engineID) {
        case .ready, .notLoaded: return .ok
        case .loading: return .busy
        case .failed: return .attention
        }
    }

    var speechLoadsOnDemand: Bool {
        let asr = container.speechConfig
        return asr.kind.isLocal && container.engineStatus.state(for: asr.engineID) == .notLoaded
            && speechTone == .ok
    }

    var speechLanguageIssue: String? {
        do { _ = try SpeechLanguagePolicy.resolve(container.speechConfig); return nil }
        catch { return error.localizedDescription }
    }

    var refinementNeedsKey: Bool {
        container.effectiveProfile.usesLLM && container.settings.llm.kind.requiresKey && !keys.refinementKeyPresent
    }

    /// Off is a valid choice, not a problem; a missing key, CLI or server is.
    var refinementTone: StatusDot.Tone {
        let llm = container.settings.llm
        if llm.kind == .none || !container.effectiveProfile.usesLLM { return .inactive }
        if llm.kind == .appleIntelligence { return facts.appleIntelligenceIssue == nil ? .ok : .attention }
        if refinementNeedsKey || facts.cliMissing { return .attention }
        switch container.models.llmStatus.state {
        case .unreachable, .failed: return .attention
        case .loading, .unknown: return .busy
        default: return .ok
        }
    }

    var refinementDetail: String {
        let llm = container.settings.llm
        guard llm.kind != .none, container.effectiveProfile.usesLLM else { return String(localized: "Off · original transcript") }
        if llm.kind == .appleIntelligence { return facts.appleIntelligenceIssue ?? String(localized: "On-device · \(container.effectiveProfile.displayName)") }
        let state = refinementNeedsKey ? String(localized: "API key needed") : container.models.llmStatus.label
        return "\(state) · \(container.effectiveProfile.displayName)"
    }
}

extension AppContainer {
    var readiness: SetupReadiness { SetupReadiness(container: self) }
}

extension View {
    /// Keeps the shared key presence current for the selected speech and refinement keys.
    func refreshesSetupCredentials(_ container: AppContainer) -> some View {
        task(id: "\(container.speechConfig.keyRef)\n\(container.settings.llm.keyRef)") {
            await container.credentialPresence.refresh(container)
        }
        .onReceive(NotificationCenter.default.publisher(for: Keychain.didChange).receive(on: DispatchQueue.main)) { _ in
            Task { await container.credentialPresence.refresh(container) }
        }
    }
}
