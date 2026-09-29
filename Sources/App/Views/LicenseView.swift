import AirdraftCore
import SwiftUI

struct LicenseView: View {
    var onClose: (() -> Void)? = nil
    @Environment(AppContainer.self) private var container
    @State private var key = ""
    @State private var confirmDeactivation = false
    @State private var confirmPending = false
    @State private var confirmForget = false
    @State private var showReplacementKey = false
    private var license: LicenseStore { container.license }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionTitleSpacing) {
            HStack {
                Text(license.configuration?.environment == .sandbox ? "Airdraft License · Sandbox" : "Airdraft License")
                    .font(.system(size: 20, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Done") { license.isPresented = false; onClose?() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    TimelineView(.periodic(from: .now, by: 60)) { _ in status }
                    if license.distribution == .official, let config = license.configuration {
                        if let label = license.deviceLabel {
                            Text("This device: \(label)").supportingText().textSelection(.enabled)
                        }
                        if license.record?.activationPending == true {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("An activation is unfinished. Check your devices before trying again.").supportingText()
                                HStack {
                                    Link("Manage Devices", destination: config.portalURL)
                                    Spacer()
                                    Button("I Removed the Pending Device…") { confirmPending = true }
                                }.font(.system(size: 12))
                            }
                        }
                        if license.access == .locked {
                            Button("Allow Access") { Task { await license.load(allowInteraction: true); await license.refresh() } }
                                .buttonStyle(.borderedProminent)
                        } else if license.record?.grant != nil {
                            HStack {
                                Button("Check License") { Task { await license.refresh() } }
                                Link("Manage Devices", destination: config.portalURL)
                                Spacer()
                                Button("Deactivate This Mac…") { confirmDeactivation = true }
                            }.buttonStyle(SoftButtonStyle())
                            if license.access == .revoked || showReplacementKey {
                                keyEntry(replacement: true)
                            } else {
                                Button("Update License Key…") { showReplacementKey = true }
                                    .buttonStyle(SoftButtonStyle())
                            }
                            if license.access == .revoked {
                                Button("I Removed This Device in the Portal…") { confirmForget = true }
                                    .buttonStyle(SoftButtonStyle())
                            }
                        } else {
                            if license.access == .needsTrial {
                                Button("Start \(config.trialDays)-Day Trial") { Task { await license.startTrial() } }
                                    .buttonStyle(.borderedProminent).controlSize(.large)
                            }
                            HStack {
                                Link(config.environment == .sandbox ? "Test Purchase" : "Buy Airdraft", destination: config.checkoutURL)
                                    .buttonStyle(SoftButtonStyle())
                                Link("Find My License", destination: config.portalURL).font(.system(size: 12))
                            }
                            keyEntry(replacement: false)
                        }
                        Text("Your purchase unlocks the official app. Cloud provider usage is billed separately; local models run on your Mac.")
                            .supportingText().fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .disabled(license.isBusy || container.pipeline.isBusy)
            }
            if license.isBusy { ProgressView().controlSize(.small).accessibilityLabel("Updating license") }
            if container.pipeline.isBusy { Text("Finish dictation before changing your license.").supportingText() }
            if let message = license.message {
                Text(message).supportingText().fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }
        .padding(Theme.pagePadding)
        .frame(width: 540, height: 500)
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

    private func keyEntry(replacement: Bool) -> some View {
        PageSection(replacement ? "Rotated your key?" : "Already purchased?") {
            SettingsCard {
                SecureField(replacement ? "Replacement license key" : "License key", text: $key)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("Airdraft license key")
                    .onSubmit { activate() }
                HStack {
                    Text(replacement ? "Keeps this Mac’s existing device slot." : "Stored in Keychain after activation.").supportingText()
                    Spacer()
                    Button(replacement ? "Update Key" : "Activate This Mac") { activate() }
                        .buttonStyle(.borderedProminent)
                        .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || license.record?.activationPending == true)
                }
            }
        }
    }

    @ViewBuilder private var status: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(statusTitle).font(.system(size: 17, weight: .semibold))
            if license.configuration?.environment == .sandbox {
                Text("Test purchases only. No real payments.").supportingText()
            }
            Text(statusDetail).font(.system(size: 13)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if license.access == .licensed, let date = license.record?.grant?.expiresAt {
                Text("Valid until \(date.formatted(date: .abbreviated, time: .omitted))").supportingText()
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusTitle: String {
        switch license.access {
        case .community: "Self-built edition"
        case .loading: "Loading your license…"
        case .unconfigured: "Licensing is not configured"
        case .needsTrial: "Try every feature"
        case .trial: "Your full-feature trial is active"
        case .licensed: "All features unlocked"
        case .expired: "Your access has expired"
        case .revoked: "This activation is no longer valid"
        case .locked: "Restore Keychain access"
        case .clockChanged: "Check your Mac’s date and time"
        }
    }
    private var statusDetail: String {
        switch license.access {
        case .community: "All features are available. No purchase or license check is required for this build."
        case .loading: "Reading the license saved on this Mac."
        case .unconfigured: "This official build cannot start a trial or accept a purchase. Contact Airdraft support for a configured build."
        case .needsTrial: "Start when you are ready. No card required. Setting up permissions and downloading models does not start the trial."
        case .trial(let end): "Available until \(end.formatted(date: .abbreviated, time: .shortened)). No automatic charge."
        case .licensed: license.isOffline ? "Offline. Using your last verified license." : "This Mac is activated. You can use local models offline."
        case .expired: "Activate a license to continue dictating. Your history and settings remain available."
        case .revoked: "If you rotated your key, update it below. Otherwise check this device in the customer portal."
        case .locked: "Allow access to your saved license. An inaccessible key is never treated as a new trial."
        case .clockChanged: "Correct the system clock to continue your trial, or activate a purchased license."
        }
    }
    private func activate() {
        guard !license.isBusy, !container.pipeline.isBusy else { return }
        Task {
            if license.record?.grant != nil { await license.updateKey(key) }
            else { await license.activate(key) }
            if license.access == .licensed, license.message == nil { key = ""; showReplacementKey = false }
        }
    }
}
