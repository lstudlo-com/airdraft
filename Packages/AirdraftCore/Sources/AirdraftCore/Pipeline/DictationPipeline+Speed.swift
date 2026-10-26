import Foundation

/// What a shortcut asks a recording to do (AD-104).
public enum DictationIntent: String, Sendable, Equatable, Codable {
    /// Ordinary dictation.
    case dictate
    /// Rewrite the current selection with the spoken instruction.
    case editSelection
}

/// How a recording was started. The main shortcut, menu and App Intents use
/// the default; profile shortcuts and the Edit shortcut fill it in.
public struct RecordingRequest: Sendable, Equatable {
    public var intent: DictationIntent
    /// A profile shortcut's profile, used instead of what app rules choose.
    public var profileID: UUID?
    /// The shortcut itself contains Shift, so Shift cannot lock a send.
    public var triggerUsesShift: Bool

    public init(intent: DictationIntent = .dictate, profileID: UUID? = nil, triggerUsesShift: Bool = false) {
        self.intent = intent
        self.profileID = profileID
        self.triggerUsesShift = triggerUsesShift
    }
}

/// Why Return is pressed after a dictation (AD-104), as History stores it.
public enum SendRequest: String, Sendable, Codable, Equatable {
    /// The user pressed Shift while recording.
    case shift
    /// The profile sends prompts to AI automatically.
    case auto
}

/// Send and flag settings, captured at recording start (AD-104).
struct SpeedOptions: Sendable, Equatable {
    var sendWithShift = false
    var flagHandling: FlagHandling = .showAndWait
    var identifiersHoldSend = true
    var sendsWhenUnconfirmed = false
    var showsFlagsAfterDictation = false
}

/// What happens after a delivered dictation that asked to send (AD-104).
enum SendDecision: Equatable {
    /// Nothing to send.
    case none
    /// Press Return once the cancel window, counted from the release, has passed.
    case send(window: Double)
    /// Flagged words hold the send; the text stays pasted.
    case hold([DictationFlag])
    /// The destination cannot send this way; the reason is shown.
    case blocked(String)
}

extension DictationPipeline {
    /// Cancel windows by how far a send can be undone, counted from the release
    /// and overlapping processing: a message to a person cannot be taken back.
    static let personSendWindow = 1.0
    static let aiSendWindow = 0.5

    /// Browsers hold mail and chat to people beside AI sites, so a profile never
    /// sends automatically in one; a Shift lock still can.
    static let browserBundlePrefixes = [
        "com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac", "org.mozilla.firefox",
        "company.thebrowser.Browser", "company.thebrowser.dia", "com.brave.Browser", "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi", "com.kagi.kagimacOS", "app.zen-browser.zen", "org.chromium.Chromium",
        "com.duckduckgo.macos.browser", "ai.perplexity.comet",
    ]

    /// A Safari or Chrome web app has its own bundle ID and counts as an app.
    static func isBrowser(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        if bundleID.hasPrefix("com.apple.Safari.WebApp") || bundleID.hasPrefix("com.google.Chrome.app.") { return false }
        return browserBundlePrefixes.contains { bundleID.hasPrefix($0) }
    }

    func speedOptions() -> SpeedOptions {
        SpeedOptions(sendWithShift: settings.sendWithShift, flagHandling: settings.flagHandling,
                     identifiersHoldSend: settings.identifiersHoldSend,
                     sendsWhenUnconfirmed: settings.sendsWhenUnconfirmed,
                     showsFlagsAfterDictation: settings.showsFlagsAfterDictation)
    }

    /// The Edit shortcut always refines: a profile that skips refinement edits
    /// with Clean's instructions. Its own destination and send never apply.
    func editProfile(from profile: RefinementProfile) -> RefinementProfile {
        var edit = profile
        if !profile.usesLLM {
            edit = profiles.profiles.first { $0.id == RefinementProfile.cleanID }
                ?? RefinementProfile.defaultProfile(id: RefinementProfile.cleanID) ?? profile
            edit.speechModel = profile.speechModel
            edit.usesLLM = true
        }
        edit.output = nil
        edit.sendsAutomatically = false
        return edit
    }

    /// Decides the send for one delivered dictation. Pure, so every rule is tested.
    static func sendDecision(request: SendRequest?, delivered: TextDeliveryStatus, bundleID: String?,
                             flags: [DictationFlag], options: SpeedOptions) -> SendDecision {
        guard let request, delivered != .notDelivered else { return .none }
        let family = AppFamily.classify(AppContext(bundleId: bundleID))
        switch request {
        case .auto:
            // Automatic sends are for AI chats and agents, never people or a browser.
            guard !isBrowser(bundleID), ![.email, .workChat, .personalChat].contains(family) else { return .none }
            guard delivered == .delivered else { return .none }
        case .shift:
            if family == .email {
                return .blocked(String(localized: "Pasted, not sent: email apps don't send with Return.", bundle: .module))
            }
            if delivered == .sentUnverified, !options.sendsWhenUnconfirmed {
                return .blocked(String(localized: "Pasted, not sent: this app can't confirm the paste.", bundle: .module))
            }
        }
        let holding = HighRiskFlags.holdingSend(flags)
        guard holding.isEmpty else { return .hold(holding) }
        return .send(window: request == .auto ? aiSendWindow : personSendWindow)
    }

    /// The recording window's text for flagged words, at most `maximumShown`.
    static func flagList(_ flags: [DictationFlag]) -> String {
        let shown = flags.prefix(HighRiskFlags.maximumShown).map { "“\($0.snippet)”" }
        let list = ListFormatter.localizedString(byJoining: Array(shown))
        let more = flags.count - shown.count
        return more > 0 ? String(localized: "\(list) and \(more) more", bundle: .module) : list
    }

    public static func heldNotice(_ flags: [DictationFlag], handling: FlagHandling) -> String {
        switch handling {
        case .showAndWait:
            String(localized: "Not sent. Check \(flagList(flags)), then press Return.", bundle: .module)
        case .pasteOnly:
            String(localized: "Pasted, not sent. Check the text, then press Return.", bundle: .module)
        }
    }

    /// The recording window's label while the Edit shortcut records.
    public static func editBadge(characters: Int) -> String {
        String(localized: "Edit · \(characters) characters", bundle: .module)
    }

    static func flagNotice(_ flags: [DictationFlag]) -> String {
        String(localized: "Check \(flagList(flags)).", bundle: .module)
    }

    // MARK: - Shift lock

    /// Watches Shift while recording. Each press toggles the lock; a Shift held
    /// when recording began counts only after it is released once.
    func startShiftMonitor(token: UUID, snapshot: RecordingSnapshot) {
        stopShiftMonitor()
        sendLocked = false
        guard snapshot.speed.sendWithShift, snapshot.request.intent == .dictate,
              !snapshot.request.triggerUsesShift, snapshot.output.target == .cursor,
              insertionEnabled, !settings.isOnboardingPractice else { return }
        var wasDown = modifierFlags() & Hotkey.maskShift != 0
        shiftMonitor = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.isCurrent(token), self.isRecording else { return }
                let down = self.modifierFlags() & Hotkey.maskShift != 0
                if down && !wasDown { self.sendLocked.toggle() }
                wasDown = down
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
    }

    func stopShiftMonitor() {
        shiftMonitor?.cancel()
        shiftMonitor = nil
    }

    /// Esc during the cancel window keeps the pasted text but presses nothing.
    public func cancelPendingSend() {
        guard isSendPending else { return }
        sendCancelled = true
    }

    /// Waits out the cancel window, then presses Return once in the original field.
    func performSend(window: Double, target: InsertionTarget?, stopRequested: TimeInterval?, token: UUID) async -> Bool? {
        isSendPending = true
        sendCancelled = false
        defer { isSendPending = false }
        let deadline = (stopRequested ?? ProcessInfo.processInfo.systemUptime) + window
        while ProcessInfo.processInfo.systemUptime < deadline {
            guard !sendCancelled, isCurrent(token) else { return nil }
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard !sendCancelled, isCurrent(token) else { return nil }
        if let pressReturn { return await pressReturn(target) }
        return await inserter.pressReturn(target: target)
    }

    // MARK: - Metrics

    /// A shortcut press arrived while an earlier dictation was still processing.
    func noteIgnoredPressIfProcessing() {
        guard state.isBusy, !isRecording, let metrics else { return }
        Task { await metrics.noteIgnoredPress() }
    }

    func noteAcceptedPress() {
        guard let metrics else { return }
        Task { await metrics.noteAcceptedPress() }
    }

    func noteCaptureMetric(ms: Int, microphone: MicrophonePreference) {
        guard let metrics else { return }
        Task.detached(priority: .utility) {
            let transport = SpeedMetricsStore.transport(for: microphone)
            await metrics.noteCapture(ms: ms, transport: transport)
        }
    }
}
