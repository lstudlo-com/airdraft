import Foundation

/// A profile an app rule can choose (AD-080) whose setup differs from the
/// chosen profile's. The pipeline checks the destination's profile at recording
/// start, so readiness checks these too: otherwise Home says Ready while
/// dictation into that app is refused.
public struct AppRuleSetup: Equatable, Sendable {
    public let rule: AppProfileRule
    /// The rule's profile as dictation would use it.
    public let profile: RefinementProfile
    /// The speech configuration the rule's profile resolves to.
    public let speech: ASRConfig
    /// Its speech model differs from the chosen profile's, so Home's Speech row
    /// does not cover it.
    public let checksSpeech: Bool
    /// It refines while the chosen profile does not, so Home's Refinement row
    /// does not cover it.
    public let checksRefinement: Bool
}

/// What would refuse a dictation into a rule's app, in the order the recording
/// prerequisites check it. Each maps to an existing setup action.
public enum AppRuleSetupIssue: Equatable, Sendable {
    /// The profile's speech binding names a model that no longer exists.
    case speechModelUnavailable
    /// The bundled catalogue for the model is damaged (reinstall message).
    case speechCatalogue(String)
    /// The shared speech language does not fit the profile's model.
    case speechLanguage(String)
    /// A local model's files are not installed, or a cloud model is unset.
    case speechModelMissing
    /// The speech endpoint is not a valid HTTP(S) URL.
    case speechEndpoint
    /// The speech provider's key is missing or locked.
    case speechKeyMissing
    /// Refinement would be required and is not usable; the recording-check message.
    case refinement(String)
}

public enum AppRuleSetupStatus: Equatable, Sendable {
    case ready
    /// A file or key fact is still being measured; not a setup step.
    case checking
    case issue(AppRuleSetupIssue)
}

/// Facts already measured for readiness. Nil means not yet known.
public struct AppRuleSetupFacts {
    public var installed: (ASRConfig) -> Bool?
    public var keyPresent: (String) -> Bool?
    public var refinementKeyPresent: Bool
    public var appleIntelligenceIssue: String?
    public var appleIntelligencePending: Bool
    public var cliMissing: Bool
    public var cliPending: Bool

    public init(installed: @escaping (ASRConfig) -> Bool?, keyPresent: @escaping (String) -> Bool?,
                refinementKeyPresent: Bool, appleIntelligenceIssue: String? = nil, appleIntelligencePending: Bool = false,
                cliMissing: Bool = false, cliPending: Bool = false) {
        self.installed = installed
        self.keyPresent = keyPresent
        self.refinementKeyPresent = refinementKeyPresent
        self.appleIntelligenceIssue = appleIntelligenceIssue
        self.appleIntelligencePending = appleIntelligencePending
        self.cliMissing = cliMissing
        self.cliPending = cliPending
    }
}

public enum AppRuleReadiness {
    /// Rules, in their order, whose profile needs a check beyond the chosen
    /// profile's. Empty while Choose profile by app is off and during practice,
    /// which always uses the chosen profile. In memory only.
    @MainActor
    public static func setups(profiles: ProfileStore, settings: AppSettings) -> [AppRuleSetup] {
        guard profiles.choosesProfileByApp, !settings.isOnboardingPractice else { return [] }
        let chosen = settings.effectiveProfile(profiles.activeProfile)
        let chosenSpeech = chosen.speechConfig(default: settings.asr)
        return profiles.appRules.compactMap { rule in
            guard let stored = profiles.profiles.first(where: { $0.id == rule.profileID }) else { return nil }
            let profile = settings.effectiveProfile(stored)
            let speech = profile.speechConfig(default: settings.asr)
            let retiredBinding = profile.speechModel?.unavailableReason != nil && profile.speechModel != chosen.speechModel
            let checksSpeech = speech != chosenSpeech || retiredBinding
            let checksRefinement = profile.usesLLM && !chosen.usesLLM
            guard checksSpeech || checksRefinement else { return nil }
            return AppRuleSetup(rule: rule, profile: profile, speech: speech,
                                checksSpeech: checksSpeech, checksRefinement: checksRefinement)
        }
    }

    /// The local speech configurations whose files readiness must measure.
    public static func localSpeechConfigs(_ setups: [AppRuleSetup]) -> [ASRConfig] {
        var configs: [ASRConfig] = []
        for setup in setups where setup.checksSpeech && setup.speech.kind.isLocal && !configs.contains(setup.speech) {
            configs.append(setup.speech)
        }
        return configs
    }

    /// Keychain references whose presence readiness must know (never values).
    public static func speechKeyRefs(_ setups: [AppRuleSetup]) -> [String] {
        var refs: [String] = []
        for setup in setups where setup.checksSpeech && !setup.speech.kind.isLocal && setup.speech.kind.preset != nil
            && !refs.contains(setup.speech.keyRef) {
            refs.append(setup.speech.keyRef)
        }
        return refs
    }

    /// Mirrors `RecordingPrerequisites.check` for the parts a rule changes;
    /// microphone, permissions and output are shared with the other Home rows.
    public static func status(of setup: AppRuleSetup, llm: LLMConfig, facts: AppRuleSetupFacts) -> AppRuleSetupStatus {
        var checking = false
        if setup.checksSpeech {
            let speech = setup.speech
            if setup.profile.speechModel?.unavailableReason != nil { return .issue(.speechModelUnavailable) }
            do { _ = try SpeechLanguagePolicy.resolve(speech) }
            catch { return .issue(.speechLanguage(error.localizedDescription)) }
            if speech.kind.isLocal {
                if let error = LocalModels.catalogueError(for: speech) { return .issue(.speechCatalogue(error.localizedDescription)) }
                switch facts.installed(speech) {
                case nil: checking = true
                case false?: return .issue(.speechModelMissing)
                case true?: break
                }
            } else {
                if speech.speechModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .issue(.speechModelMissing) }
                if speech.kind == .openAICompatible, !RecordingPrerequisites.isValidEndpoint(speech.baseURL) {
                    return .issue(.speechEndpoint)
                }
                if speech.kind.preset != nil {
                    switch facts.keyPresent(speech.keyRef) {
                    case nil: checking = true
                    case false?: return .issue(.speechKeyMissing)
                    case true?: break
                    }
                }
            }
        }
        if setup.checksRefinement, llm.kind != .none {
            if llm.kind == .appleIntelligence {
                if facts.appleIntelligencePending { checking = true }
                else if let reason = facts.appleIntelligenceIssue { return .issue(.refinement(reason)) }
            }
            if llm.kind.requiresKey, !facts.refinementKeyPresent {
                return .issue(.refinement(String(localized: "Add a refinement API key in Models, or turn refinement Off.", bundle: .module)))
            }
            if llm.kind.isCLI {
                if facts.cliPending { checking = true }
                else if facts.cliMissing {
                    return .issue(.refinement(String(localized: "Set up the refinement CLI in Models, or turn it Off.", bundle: .module)))
                }
            }
            if llm.kind == .openAICompatible, !RecordingPrerequisites.isValidEndpoint(llm.baseURL) {
                return .issue(.refinement(String(localized: "Check the refinement endpoint in Models.", bundle: .module)))
            }
        }
        return checking ? .checking : .ready
    }
}
