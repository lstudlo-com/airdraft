import AirdraftCore
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

/// The one readiness model behind Home's setup card and hero and the sidebar footer.
@MainActor
struct SetupReadiness {
    let container: AppContainer
    private var keys: SetupCredentialPresence { container.credentialPresence }

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
        setupIssueCount == 0 && blockers == [.waitingRecordings] ? "Recordings Waiting" : "Finish Setup"
    }

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
            ? ScriptDelivery.unavailableReason(path: container.settings.outputScriptPath) == nil
            : container.permissions.accessibilityGranted
    }

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
        if !LocalModels.isInstalled(asr) { return String(localized: "Model not installed") }
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
        guard LocalModels.isInstalled(asr) else { return .attention }
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
        if llm.kind == .appleIntelligence { return AppleIntelligenceRefiner.unavailableReason == nil ? .ok : .attention }
        if refinementNeedsKey || (llm.kind.isCLI && llm.cliExecutable == nil) { return .attention }
        switch container.models.llmStatus.state {
        case .unreachable, .failed: return .attention
        case .loading, .unknown: return .busy
        default: return .ok
        }
    }

    var refinementDetail: String {
        let llm = container.settings.llm
        guard llm.kind != .none, container.effectiveProfile.usesLLM else { return String(localized: "Off · original transcript") }
        if llm.kind == .appleIntelligence { return AppleIntelligenceRefiner.unavailableReason ?? String(localized: "On-device · \(container.effectiveProfile.name)") }
        let state = refinementNeedsKey ? String(localized: "API key needed") : container.models.llmStatus.label
        return "\(state) · \(container.effectiveProfile.name)"
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
