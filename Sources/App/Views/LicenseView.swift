import AirdraftCore
import AppKit
import SwiftUI

/// The license sheet. It opens with the app's identity and current state, offers the
/// one action that moves the customer forward, and keeps anything that manages an
/// existing activation in paired rows beneath. Copy appears only where it changes a
/// decision: cost, privacy and recovery.
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
            let current = status(now: timeline.date)
            VStack(alignment: .leading, spacing: Theme.pagePadding) {
                header(current)
                if license.distribution == .official, let config = license.configuration {
                    sections(config, now: timeline.date)
                        .disabled(license.isBusy || container.pipeline.isBusy)
                }
                notices
            }
            .padding(Theme.pagePadding)
        }
    }

    private func header(_ status: Status) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                SidebarBrandMark(height: 36, identifier: "license.brand")
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Airdraft")
                            .font(.system(size: 17, weight: .semibold))
                            .accessibilityLabel("Airdraft License")
                            .accessibilityAddTraits(.isHeader)
                        if isSandbox { PillTag(text: "SANDBOX") }
                    }
                    stateLine(status)
                }
                Spacer(minLength: Theme.controlSpacing)
                Button("Done") { license.isPresented = false; onClose?() }
                    .buttonStyle(SoftButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            if status.detail != nil || isSandbox {
                VStack(alignment: .leading, spacing: 6) {
                    if let detail = status.detail {
                        Text(detail)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if isSandbox { Text("Test purchases only. No real payments.").supportingText() }
                }
            }
        }
    }

    private func stateLine(_ status: Status) -> some View {
        HStack(spacing: 6) {
            if license.isBusy {
                ProgressView().controlSize(.mini).frame(width: 8, height: 8)
                    .accessibilityLabel("Updating license")
            } else if let tone = status.tone {
                StatusDot(tone)
            }
            Text(status.title).font(.system(size: 13, weight: .medium))
            if let qualifier = status.qualifier {
                Text("· \(qualifier)").font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
    }

    /// What the customer can do now. Recovery of an unfinished activation always leads.
    @ViewBuilder
    private func sections(_ config: PolarConfiguration, now: Date) -> some View {
        if isPending { recovery(config) }
        switch license.access {
        case .community, .loading, .unconfigured:
            EmptyView()
        case .locked:
            Button("Allow Access") { Task { await license.load(allowInteraction: true); await license.refresh() } }
                .buttonStyle(.borderedProminent)
        default:
            if hasGrant { activation(config, now: now) } else { purchase(config) }
        }
    }

    /// An activation whose outcome is unknown may hold a device slot; never retry automatically.
    private func recovery(_ config: PolarConfiguration) -> some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    StatusDot(.attention)
                    Text("Activation unfinished").font(.system(size: 13, weight: .medium))
                }
                Text("A previous attempt may have used a device slot. Remove “\(license.deviceLabel ?? "this Mac")” in your customer portal, then confirm here.")
                    .supportingText()
                    .textSelection(.enabled)
                    .padding(.leading, 16)
            }
            HStack(spacing: 8) {
                styled(Link("Manage Devices", destination: config.portalURL), prominent: true)
                Button("I Removed It…") { confirmPending = true }
                    .buttonStyle(SoftButtonStyle())
            }
        }
    }

    // MARK: Not activated

    private func purchase(_ config: PolarConfiguration) -> some View {
        let needsTrial = license.access == .needsTrial
        return VStack(alignment: .leading, spacing: Theme.pagePadding) {
            HStack(spacing: 8) {
                if needsTrial {
                    styled(Button("Start \(config.trialDays)-Day Trial") { Task { await license.startTrial() } },
                           prominent: !isPending)
                }
                styled(Link(config.environment == .sandbox ? "Test Purchase" : "Buy Airdraft", destination: config.checkoutURL),
                       prominent: !isPending && (isTrialActive || license.access == .expired))
            }
            VStack(alignment: .leading, spacing: Theme.controlSpacing) {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("License key").font(.system(size: 13, weight: .medium))
                            Spacer(minLength: Theme.controlSpacing)
                            Link(destination: config.portalURL) {
                                HStack(spacing: 3) {
                                    Text("Find My License")
                                    Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .semibold))
                                }
                            }
                            .font(.system(size: 12))
                        }
                        keyField(replacement: false, prominent: false)
                        Text("Stored in Keychain after activation.").supportingText()
                    }
                }
                Text("Cloud provider usage is billed separately. Local models run on your Mac.").supportingText()
            }
        }
    }

    // MARK: Activated

    private func activation(_ config: PolarConfiguration, now: Date) -> some View {
        let grant = license.record?.grant
        let revoked = license.access == .revoked
        return VStack(alignment: .leading, spacing: Theme.controlSpacing) {
            SettingsCard {
                SettingRow(title: "This Mac", subtitle: license.deviceLabel) {
                    styled(Link("Manage Devices", destination: config.portalURL), prominent: false)
                }
                .textSelection(.enabled)
                if let end = grant?.expiresAt {
                    RowDivider()
                    SettingRow(title: end > now ? "Valid until" : "Expired",
                               subtitle: end.formatted(date: .abbreviated, time: .omitted)) {}
                }
                if let verified = grant?.verifiedAt {
                    RowDivider()
                    SettingRow(title: "Last checked", subtitle: verified.formatted(date: .abbreviated, time: .shortened)) {
                        Button("Check License") { Task { await license.refresh() } }
                            .buttonStyle(SoftButtonStyle())
                    }
                }
                if !revoked {
                    RowDivider()
                    SettingRow(title: "License key", subtitle: "Stored in Keychain") {
                        Button(showReplacementKey ? "Cancel" : "Update Key…") {
                            showReplacementKey.toggle()
                            key = ""
                        }
                        .buttonStyle(SoftButtonStyle())
                    }
                }
                if revoked || showReplacementKey {
                    RowDivider()
                    VStack(alignment: .leading, spacing: 8) {
                        keyField(replacement: true, prominent: revoked)
                        Text("Keeps this Mac’s existing device slot.").supportingText()
                    }
                }
            }
            HStack(spacing: 8) {
                Button("Deactivate This Mac…") { confirmDeactivation = true }
                if revoked { Button("I Removed This Device…") { confirmForget = true } }
            }
            .buttonStyle(SoftButtonStyle())
        }
    }

    // MARK: Shared pieces

    private func keyField(replacement: Bool, prominent: Bool) -> some View {
        HStack(spacing: 8) {
            SecureField(replacement ? "Replacement license key" : "Paste your key", text: $key)
                .textFieldStyle(.roundedBorder)
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

    @ViewBuilder private var notices: some View {
        if container.pipeline.isBusy {
            InlineNotice("Finish dictation before changing your license.") { EmptyView() }
        }
        if let message = visibleMessage {
            InlineNotice(message) { EmptyView() }
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

    // MARK: State

    private struct Status {
        let title: String
        var qualifier: String? = nil
        /// Nil when the state needs no indicator: a self-built edition has nothing to go wrong.
        let tone: StatusDot.Tone?
        var detail: String? = nil
    }

    private func status(now: Date) -> Status {
        var status = baseStatus(now: now)
        if isPending { status.detail = nil }
        // The failure notice already says why; the detail only stands in when it is gone.
        if license.isOffline, license.message != nil { status.detail = nil }
        return status
    }

    private func baseStatus(now: Date) -> Status {
        switch license.access {
        case .community:
            return Status(title: "Self-built edition", tone: nil,
                          detail: "Every feature is unlocked. This build needs no license.")
        case .loading:
            return Status(title: "Checking license…", tone: .busy)
        case .unconfigured:
            return Status(title: "Not configured", tone: .attention,
                          detail: "This build can’t start a trial or accept a purchase. Contact Airdraft support for a configured build.")
        case .needsTrial:
            return Status(title: "Not activated", tone: .inactive,
                          detail: "Try every feature free for \(Self.days(license.configuration?.trialDays ?? 14)). No card required.")
        case .trial(let end):
            return Status(title: "Trial", qualifier: Self.remaining(until: end, now: now), tone: .ok,
                          detail: "Full access until \(end.formatted(date: .abbreviated, time: .shortened)). No automatic charge.")
        case .licensed:
            return Status(title: "Licensed", qualifier: license.isOffline ? "Offline" : nil, tone: .ok,
                          detail: license.isOffline ? "Using your last verified license." : nil)
        case .expired:
            return Status(title: hasGrant ? "License expired" : "Trial ended", tone: .attention,
                          detail: "Buy or activate a license to keep dictating. Your history and settings stay available.")
        case .revoked:
            return Status(title: "Activation invalid", tone: .attention,
                          detail: "If you rotated your key, enter the new one below. Otherwise check this Mac in your customer portal.")
        case .locked:
            return Status(title: "Keychain locked", tone: .attention,
                          detail: "Allow access to read your saved license. A locked license never restarts your trial.")
        case .clockChanged:
            return Status(title: "Clock changed", tone: .attention,
                          detail: "Correct your Mac’s date and time to continue the trial, or activate a license.")
        }
    }

    private static func days(_ count: Int) -> String { "\(count) day\(count == 1 ? "" : "s")" }

    /// Whole days, rounded up, so a fresh 14-day trial reads 14.
    private static func remaining(until end: Date, now: Date) -> String {
        let seconds = end.timeIntervalSince(now)
        guard seconds > 0 else { return "Ending now" }
        return "\(days(Int((seconds / 86_400).rounded(.up)))) left"
    }
}
