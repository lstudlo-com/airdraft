import AirdraftCore
import AppKit
import SwiftUI

/// The license sheet: the brand mark, one headline, one sentence and the few buttons
/// that apply. It is plain text on the sheet, with no cards, badges or status lights.
struct LicenseView: View {
    var onClose: (() -> Void)? = nil
    @Environment(AppContainer.self) private var container
    @State private var key = ""
    @State private var confirmDeactivation = false
    @State private var confirmPending = false
    @State private var confirmForget = false
    @State private var showReplacementKey = false
    private var license: LicenseStore { container.license }

    /// The sheet is as tall as its content, and scrolls only past this height so it
    /// still fits the window's 600-point minimum.
    private static let width: CGFloat = 440
    private static let maxHeight: CGFloat = 520

    private var isSandbox: Bool { license.configuration?.environment == .sandbox }
    private var hasGrant: Bool { license.record?.grant != nil }
    private var isPending: Bool { license.record?.activationPending == true }
    private var isTrialActive: Bool { if case .trial = license.access { true } else { false } }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        .frame(width: Self.width)
        .frame(maxHeight: Self.maxHeight)
        .confirmationDialog("Deactivate this Mac?", isPresented: $confirmDeactivation) {
            Button("Deactivate This Mac", role: .destructive) { Task { await license.deactivate() } }
        } message: { Text("This releases its device slot. Your history, models and provider keys stay on this Mac.") }
        .confirmationDialog("Have you removed the unfinished activation in the customer portal?", isPresented: $confirmPending) {
            Button("I Removed It") { Task { await license.acknowledgePendingActivation() } }
        } message: { Text("Trying again before removing it may use another device slot.") }
        .confirmationDialog("Did you remove \(license.deviceLabel ?? "this device") in the customer portal?", isPresented: $confirmForget) {
            Button("Forget Removed Device", role: .destructive) { Task { await license.forgetRemovedActivation() } }
        } message: { Text("This only clears the saved activation on this Mac. It cannot release a device slot in Polar. For a rotated key, use Update Key instead.") }
    }

    // MARK: Layout

    /// Re-read every minute so a trial's countdown and expiry stay true while the sheet is open.
    private var content: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let summary = summary(now: timeline.date)
            VStack(alignment: .leading, spacing: 20) {
                topBar
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary.title)
                        .font(.system(size: 17, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    if let detail = summary.detail {
                        Text(detail)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if isSandbox { Text("Test purchases only. No real payments.").supportingText() }
                }
                if license.distribution == .official, let config = license.configuration {
                    sections(config, now: timeline.date)
                        .disabled(license.isBusy || container.pipeline.isBusy)
                }
                if container.pipeline.isBusy {
                    Text("Finish dictation before changing your license.").supportingText()
                }
                if let message = visibleMessage {
                    Text(message).supportingText().textSelection(.enabled)
                }
            }
            .padding(Theme.pagePadding)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            SidebarBrandMark(height: 32, identifier: "license.brand")
                .accessibilityHidden(true)
            if isSandbox { PillTag(text: "SANDBOX") }
            Spacer(minLength: Theme.controlSpacing)
            if license.isBusy {
                ProgressView().controlSize(.small).accessibilityLabel("Updating license")
            }
            Button("Done") { license.isPresented = false; onClose?() }
                .buttonStyle(SoftButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
    }

    /// What the customer can do now. Recovery of an unfinished activation always leads.
    @ViewBuilder
    private func sections(_ config: PolarConfiguration, now: Date) -> some View {
        if isPending {
            HStack(spacing: 8) {
                styled(Link("Manage Devices", destination: config.portalURL), prominent: true)
                Button("I Removed It…") { confirmPending = true }
                    .buttonStyle(SoftButtonStyle())
            }
        }
        switch license.access {
        case .community, .loading, .unconfigured:
            EmptyView()
        case .locked:
            Button("Allow Access") { Task { await license.load(allowInteraction: true); await license.refresh() } }
                .buttonStyle(.borderedProminent)
        default:
            if hasGrant { activation(config) } else { purchase(config) }
        }
    }

    // MARK: Not activated

    private func purchase(_ config: PolarConfiguration) -> some View {
        let needsTrial = license.access == .needsTrial
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                if needsTrial {
                    styled(Button("Start \(config.trialDays)-Day Trial") { Task { await license.startTrial() } },
                           prominent: !isPending)
                }
                styled(Link(config.environment == .sandbox ? "Test Purchase" : "Buy Airdraft", destination: config.checkoutURL),
                       prominent: !isPending && (isTrialActive || license.access == .expired))
            }
            VStack(alignment: .leading, spacing: 8) {
                keyField(replacement: false, prominent: false)
                Link("Find My License", destination: config.portalURL).font(.system(size: 12))
            }
        }
    }

    // MARK: Activated

    private func activation(_ config: PolarConfiguration) -> some View {
        let revoked = license.access == .revoked
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Button("Check License") { Task { await license.refresh() } }
                styled(Link("Manage Devices", destination: config.portalURL), prominent: false)
                if !revoked {
                    Button(showReplacementKey ? "Cancel" : "Update Key…") {
                        showReplacementKey.toggle()
                        key = ""
                    }
                }
            }
            .buttonStyle(SoftButtonStyle())
            if revoked || showReplacementKey {
                keyField(replacement: true, prominent: revoked)
            }
            HStack(spacing: 16) {
                Button("Deactivate This Mac…") { confirmDeactivation = true }
                if revoked { Button("I Removed This Device…") { confirmForget = true } }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Shared pieces

    private func keyField(replacement: Bool, prominent: Bool) -> some View {
        HStack(spacing: 8) {
            SecureField(replacement ? "New license key" : "License key", text: $key)
                .softField()
                .accessibilityLabel("Airdraft license key")
                .onSubmit { activate() }
                .disabled(isPending)
            styled(Button(replacement ? "Update Key" : "Activate This Mac") { activate() }.fixedSize(), prominent: prominent)
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPending)
        }
    }

    /// One prominent action per state; every other control uses the shared soft capsule.
    @ViewBuilder
    private func styled<Control: View>(_ control: Control, prominent: Bool) -> some View {
        if prominent {
            control.buttonStyle(.borderedProminent)
        } else {
            control.buttonStyle(SoftButtonStyle())
        }
    }

    /// Hide a failure the state's own explanation already gives.
    private var visibleMessage: String? {
        guard let message = license.message else { return nil }
        if license.access == .locked, message == LicenseError.storageLocked.errorDescription { return nil }
        if isPending, message == LicenseError.activationUncertain.errorDescription { return nil }
        return message
    }

    private func activate() {
        guard !license.isBusy, !container.pipeline.isBusy else { return }
        Task {
            if license.record?.grant != nil { await license.updateKey(key) }
            else { await license.activate(key) }
            if license.access == .licensed, license.message == nil { key = ""; showReplacementKey = false }
        }
    }

    // MARK: Words

    private struct Summary {
        let title: String
        var detail: String? = nil
    }

    private func summary(now: Date) -> Summary {
        let label = license.deviceLabel ?? "this Mac"
        if isPending {
            return Summary(title: "Activation unfinished",
                           detail: "A previous attempt may have used a device slot. Remove “\(label)” in your customer portal, then confirm.")
        }
        switch license.access {
        case .community:
            return Summary(title: "Self-built edition", detail: "Every feature is unlocked. This build needs no license.")
        case .loading:
            return Summary(title: "Checking license…")
        case .unconfigured:
            return Summary(title: "Not configured",
                           detail: "This build can’t start a trial or accept a purchase. Contact Airdraft support for a configured build.")
        case .needsTrial:
            return Summary(title: "Try every feature free for \(Self.days(license.configuration?.trialDays ?? 14))",
                           detail: "No card required.")
        case .trial(let end):
            return Summary(title: "\(Self.remaining(until: end, now: now)) left in your trial",
                           detail: "Full access until \(end.formatted(date: .abbreviated, time: .shortened)). No automatic charge.")
        case .licensed:
            let offline = license.isOffline && license.message == nil
            return Summary(title: "Licensed", detail: [
                "This Mac: \(label)",
                license.record?.grant?.expiresAt.map { "Valid until \($0.formatted(date: .abbreviated, time: .omitted))." },
                offline ? "Offline. Using your last verified license." : nil,
            ].compactMap { $0 }.joined(separator: "\n"))
        case .expired:
            return Summary(title: hasGrant ? "Your license has expired" : "Your trial has ended",
                           detail: "Buy or activate a license to keep dictating. Your history and settings stay available.")
        case .revoked:
            return Summary(title: "This activation is no longer valid",
                           detail: "If you rotated your key, enter the new one. Otherwise check “\(label)” in your customer portal.")
        case .locked:
            return Summary(title: "Keychain access needed",
                           detail: "Allow access to read your saved license. A locked license never restarts your trial.")
        case .clockChanged:
            return Summary(title: "Check your Mac’s date and time",
                           detail: "Correct the clock to continue your trial, or activate a license.")
        }
    }

    private static func days(_ count: Int) -> String { "\(count) day\(count == 1 ? "" : "s")" }

    /// Whole days, rounded up, so a fresh 14-day trial reads 14.
    private static func remaining(until end: Date, now: Date) -> String {
        let seconds = end.timeIntervalSince(now)
        guard seconds > 0 else { return "No time" }
        return days(Int((seconds / 86_400).rounded(.up)))
    }
}
