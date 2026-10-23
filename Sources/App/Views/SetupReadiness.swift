import AirdraftCore
import AppKit
import SwiftUI

/// Whether the current speech and refinement keys are saved. Home and the sidebar
/// read the same values, so they never disagree about setup.
@MainActor @Observable
final class SetupCredentialPresence {
    private(set) var speechKeyPresent = false
    private(set) var refinementKeyPresent = false
    /// Speech keys of profiles that app rules choose (AD-080), by reference.
    /// A reference not yet checked is absent, which readiness shows as checking.
    private(set) var ruleSpeechKeys: [String: Bool] = [:]

    /// Presence only: never reads a key value or prompts.
    func refresh(_ container: AppContainer) async {
        guard !RenderMode.isActive, !RenderMode.excludesCredentials else { return }
        let speech = container.speechConfig.keyRef
        let refinement = container.settings.llm.keyRef
        let rules = container.appRuleSpeechKeyRefs
        let present = await Task.detached {
            (Keychain.presence(speech) == .saved, Keychain.presence(refinement) == .saved,
             Dictionary(uniqueKeysWithValues: rules.map { ($0, Keychain.presence($0) == .saved) }))
        }.value
        guard !Task.isCancelled else { return }
        if container.speechConfig.keyRef == speech { speechKeyPresent = present.0 }
        if container.settings.llm.keyRef == refinement { refinementKeyPresent = present.1 }
        if container.appRuleSpeechKeyRefs == rules { ruleSpeechKeys = present.2 }
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
        /// Other local speech models that app rules choose (AD-080).
        var ruleSpeech: [ASRConfig] = []
    }

    struct Values: Equatable, Sendable {
        var speechInstalled = false
        var scriptIssue: String?
        var appleIntelligenceIssue: String?
        var cliMissing = false
        /// Installed state of each measured `Inputs.ruleSpeech` model; an
        /// unmeasured model is absent and `pending` holds `.ruleSpeech`.
        var ruleSpeech: [RuleSpeech] = []
        /// Facts not yet measured for the current inputs. Readiness shows them as
        /// being checked instead of measuring on the main actor.
        var pending: Set<Fact> = []

        func ruleSpeechInstalled(_ config: ASRConfig) -> Bool? {
            ruleSpeech.first { $0.config == config }?.installed
        }
    }

    struct RuleSpeech: Equatable, Sendable {
        var config: ASRConfig
        var installed: Bool
    }

    enum Fact: Hashable, Sendable { case speech, script, appleIntelligence, cli, ruleSpeech }

    /// Recent measurements, newest first, keyed by their inputs. Switching back
    /// to an earlier model or script shows its last-known facts until the
    /// refresh for those inputs lands.
    private(set) var measurements: [(inputs: Inputs, values: Values)] = []
    private static let measurementLimit = 8
    @ObservationIgnored private var refreshID = UUID()
    @ObservationIgnored private var downloadSignature: [String: Bool] = [:]
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    private let measurer: @Sendable (Inputs) -> Values
    private let measuresDuringRenders: Bool

    /// Fixtures inject the measurement and turn off the render shortcut below.
    init(measurer: @escaping @Sendable (Inputs) -> Values = { SetupFacts.measure($0) }, measuresDuringRenders: Bool = true) {
        self.measurer = measurer
        self.measuresDuringRenders = measuresDuringRenders
    }

    /// The current values, never measured here: view bodies call this on every
    /// redraw. Facts whose inputs have no measurement yet are `pending` until
    /// the off-main refresh (started whenever the inputs change) lands.
    func values(for inputs: Inputs) -> Values {
        if let exact = measurements.first(where: { $0.inputs == inputs }) { return exact.values }
        // Debug renders and fixtures draw once without starting refreshes.
        if measuresDuringRenders, RenderMode.isActive { return measurer(inputs) }
        var values = Values()
        func known<T>(_ fact: Fact, _ relevant: (Inputs) -> Bool, _ value: (Values) -> T) -> T? {
            guard let match = measurements.first(where: { relevant($0.inputs) }) else {
                values.pending.insert(fact)
                return nil
            }
            return value(match.values)
        }
        if !inputs.speech.kind.isLocal {
            values.speechInstalled = true
        } else if let installed = known(.speech, { $0.speech == inputs.speech }, \.speechInstalled) {
            values.speechInstalled = installed
        }
        if inputs.scriptPath != nil {
            values.scriptIssue = known(.script, { $0.scriptPath == inputs.scriptPath }, \.scriptIssue) ?? nil
        }
        if inputs.llm.kind == .appleIntelligence {
            values.appleIntelligenceIssue = known(.appleIntelligence, { $0.llm.kind == .appleIntelligence }, \.appleIntelligenceIssue) ?? nil
        }
        if inputs.llm.kind.isCLI {
            let kind = inputs.llm.kind
            values.cliMissing = known(.cli, { $0.llm.kind == kind && $0.llm.cliPaths[kind.rawValue] == inputs.llm.cliPaths[kind.rawValue] },
                                      \.cliMissing) ?? false
        }
        for config in inputs.ruleSpeech {
            let installed = measurements.lazy.compactMap { measurement -> Bool? in
                if measurement.inputs.speech == config { return measurement.values.speechInstalled }
                return measurement.values.ruleSpeechInstalled(config)
            }.first
            if let installed { values.ruleSpeech.append(RuleSpeech(config: config, installed: installed)) }
            else { values.pending.insert(.ruleSpeech) }
        }
        return values
    }

    /// Measures off the main actor; a newer refresh rejects an older result.
    func refresh(_ inputs: Inputs) async {
        let token = UUID()
        refreshID = token
        let measurer = measurer
        let values = await Task.detached(priority: .userInitiated) { measurer(inputs) }.value
        guard refreshID == token else { return }
        if measurements.first?.inputs == inputs, measurements.first?.values == values { return }
        measurements = [(inputs, values)] + measurements.filter { $0.inputs != inputs }.prefix(Self.measurementLimit - 1)
    }

    nonisolated static func measure(_ inputs: Inputs) -> Values {
        var values = Values()
        values.speechInstalled = !inputs.speech.kind.isLocal || LocalModels.isInstalled(inputs.speech)
        values.scriptIssue = inputs.scriptPath.flatMap { ScriptDelivery.unavailableReason(path: $0) }
        if inputs.llm.kind == .appleIntelligence { values.appleIntelligenceIssue = AppleIntelligenceRefiner.unavailableReason }
        values.cliMissing = inputs.llm.kind.isCLI && inputs.llm.cliExecutable == nil
        values.ruleSpeech = inputs.ruleSpeech.map { RuleSpeech(config: $0, installed: LocalModels.isInstalled($0)) }
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
            guard measurements.first?.inputs != inputs || signature != downloadSignature else { return }
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

/// Whether the chosen profile's speech model can show live text (AD-084),
/// from `SetupFacts` only: Settings redraws never stat the model folder.
enum ModelPreviewReadiness: Equatable {
    case ready
    /// The model's files are still being measured.
    case checking
    case unavailable(String)

    /// `facts` must be the values for inputs whose `speech` is `speech`.
    static func of(_ speech: ASRConfig, facts: SetupFacts.Values) -> ModelPreviewReadiness {
        if !ModelSpeechPreview.supports(speech) || !facts.pending.contains(.speech),
           let reason = ModelSpeechPreview.unavailableReason(for: speech, installed: facts.speechInstalled) {
            return .unavailable(reason)
        }
        return facts.pending.contains(.speech) ? .checking : .ready
    }
}

extension AppContainer {
    /// Live-text readiness of the model `setupFactsInputs.speech` names.
    var modelPreviewReadiness: ModelPreviewReadiness {
        ModelPreviewReadiness.of(speechConfig, facts: setupFacts.values(for: setupFactsInputs))
    }

    var setupFactsInputs: SetupFacts.Inputs {
        SetupFacts.Inputs(speech: speechConfig,
                          scriptPath: settings.outputDestination == .script ? settings.outputScriptPath : nil,
                          llm: settings.llm,
                          ruleSpeech: AppRuleReadiness.localSpeechConfigs(appRuleSetups).filter { $0 != speechConfig })
    }

    /// Profiles app rules choose whose setup differs from the chosen one's (AD-080).
    var appRuleSetups: [AppRuleSetup] { AppRuleReadiness.setups(profiles: profiles, settings: settings) }
    var appRuleSpeechKeyRefs: [String] { AppRuleReadiness.speechKeyRefs(appRuleSetups) }
}

/// The one readiness model behind Home's setup card and hero and the sidebar
/// footer. Everything it reads is in memory: file and system checks come from
/// `SetupFacts`, and a fact still being measured shows as Checking (busy, not a
/// setup step) rather than being measured during a redraw.
@MainActor
struct SetupReadiness {
    let container: AppContainer
    private var keys: SetupCredentialPresence { container.credentialPresence }
    private var facts: SetupFacts.Values { container.setupFacts.values(for: container.setupFactsInputs) }

    /// Setup rows plus the license and kept-recording bounds the pipeline enforces,
    /// so Home never says Ready while the shortcut would be refused.
    var issueCount: Int { setupIssueCount + blockers.count }

    var setupIssueCount: Int {
        [container.hotkeys.isActive, outputReady, microphoneReady, speechTone != .attention, refinementTone != .attention,
         appRuleIssues.isEmpty]
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

    /// A script still being checked is not counted as a setup step.
    var outputReady: Bool {
        container.settings.outputDestination == .script
            ? facts.scriptIssue == nil
            : container.permissions.accessibilityGranted
    }

    var scriptTone: StatusDot.Tone {
        facts.pending.contains(.script) ? .busy : facts.scriptIssue == nil ? .ok : .attention
    }

    /// Home's Script output row: the problem, or the script's file name.
    var scriptDetail: String {
        if facts.pending.contains(.script) { return String(localized: "Checking script…") }
        return facts.scriptIssue ?? URL(fileURLWithPath: container.settings.outputScriptPath).lastPathComponent
    }

    /// The selected speech model's files are on disk, or it needs none.
    /// False while they are still being checked.
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
        if facts.pending.contains(.speech) { return String(localized: "Checking model files…") }
        if !facts.speechInstalled {
            // A damaged bundled catalogue cannot be fixed by downloading.
            return LocalModels.catalogueError(for: asr)?.localizedDescription ?? String(localized: "Model not installed")
        }
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
        if facts.pending.contains(.speech) { return .busy }
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

    // MARK: Profiles chosen by app (AD-080)

    /// Rules whose profile would refuse dictation into their app, in rule order.
    /// Facts still being measured are not issues.
    var appRuleIssues: [(setup: AppRuleSetup, issue: AppRuleSetupIssue)] {
        let setups = container.appRuleSetups
        guard !setups.isEmpty else { return [] }
        let facts = self.facts
        let speech = container.speechConfig
        let ruleFacts = AppRuleSetupFacts(
            installed: { $0 == speech ? (facts.pending.contains(.speech) ? nil : facts.speechInstalled) : facts.ruleSpeechInstalled($0) },
            keyPresent: { [keys] ref in keys.ruleSpeechKeys[ref] },
            refinementKeyPresent: keys.refinementKeyPresent,
            appleIntelligenceIssue: facts.appleIntelligenceIssue,
            appleIntelligencePending: facts.pending.contains(.appleIntelligence),
            cliMissing: facts.cliMissing,
            cliPending: facts.pending.contains(.cli))
        return setups.compactMap { setup in
            guard case .issue(let issue) = AppRuleReadiness.status(of: setup, llm: container.settings.llm, facts: ruleFacts) else { return nil }
            return (setup, issue)
        }
    }

    /// Home's App rules row: the first blocked rule, naming its app and profile.
    var appRuleDetail: String {
        let issues = appRuleIssues
        guard let first = issues.first else { return "" }
        let app = AppRuleTitle.title(first.setup.rule)
        let profile = first.setup.profile.displayName
        let detail: String
        switch first.issue {
        case .speechModelUnavailable: detail = String(localized: "\(app) uses \(profile), whose speech model is no longer available")
        case .speechCatalogue(let message): detail = String(localized: "\(app) uses \(profile). \(message)")
        case .speechLanguage: detail = String(localized: "\(app) uses \(profile), whose speech model doesn't support the selected language")
        case .speechModelMissing: detail = String(localized: "\(app) uses \(profile), whose speech model isn't installed")
        case .speechEndpoint: detail = String(localized: "\(app) uses \(profile), whose speech endpoint needs checking")
        case .speechKeyMissing: detail = String(localized: "\(app) uses \(profile), whose speech API key is missing or locked")
        case .refinement: detail = String(localized: "\(app) uses \(profile), which refines, but refinement isn't set up")
        }
        switch issues.count {
        case 1: return detail
        case 2: return detail + " " + String(localized: "1 more app rule needs setup.")
        default: return detail + " " + String(localized: "\(issues.count - 1) more app rules need setup.")
        }
    }

    var refinementNeedsKey: Bool {
        container.effectiveProfile.usesLLM && container.settings.llm.kind.requiresKey && !keys.refinementKeyPresent
    }

    /// Off is a valid choice, not a problem; a missing key, CLI or server is.
    var refinementTone: StatusDot.Tone {
        let llm = container.settings.llm
        if llm.kind == .none || !container.effectiveProfile.usesLLM { return .inactive }
        if llm.kind == .appleIntelligence {
            if facts.pending.contains(.appleIntelligence) { return .busy }
            return facts.appleIntelligenceIssue == nil ? .ok : .attention
        }
        if refinementNeedsKey || facts.cliMissing { return .attention }
        if facts.pending.contains(.cli) { return .busy }
        switch container.models.llmStatus.state {
        case .unreachable, .failed: return .attention
        case .loading, .unknown: return .busy
        default: return .ok
        }
    }

    var refinementDetail: String {
        let llm = container.settings.llm
        guard llm.kind != .none, container.effectiveProfile.usesLLM else { return String(localized: "Off · original transcript") }
        if llm.kind == .appleIntelligence {
            if facts.pending.contains(.appleIntelligence) { return String(localized: "Checking Apple Intelligence…") }
            return facts.appleIntelligenceIssue ?? String(localized: "On-device · \(container.effectiveProfile.displayName)")
        }
        let state = refinementNeedsKey ? String(localized: "API key needed") : container.models.llmStatus.label
        return "\(state) · \(container.effectiveProfile.displayName)"
    }
}

extension AppContainer {
    var readiness: SetupReadiness { SetupReadiness(container: self) }
}

/// A rule's app or family name, as the Profiles rule list shows it.
enum AppRuleTitle {
    @MainActor
    static func title(_ rule: AppProfileRule) -> String {
        switch rule.match {
        case .family(let family): family.ruleTitle
        case .app(let bundleID): InstalledApplications.entry(for: bundleID).name ?? rule.appName ?? bundleID
        }
    }
}

extension View {
    /// Keeps the shared key presence current for the selected speech and refinement keys.
    func refreshesSetupCredentials(_ container: AppContainer) -> some View {
        task(id: "\(container.speechConfig.keyRef)\n\(container.settings.llm.keyRef)\n\(container.appRuleSpeechKeyRefs.joined(separator: ","))") {
            await container.credentialPresence.refresh(container)
        }
        .onReceive(NotificationCenter.default.publisher(for: Keychain.didChange).receive(on: DispatchQueue.main)) { _ in
            Task { await container.credentialPresence.refresh(container) }
        }
    }
}
