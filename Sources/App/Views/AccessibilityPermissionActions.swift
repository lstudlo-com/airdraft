import AirdraftCore
import Security
import SwiftUI

/// The same recovery flow is available from Home and Configuration.
struct AccessibilityPermissionActions: View {
    @State private var showingHelp = false

    var body: some View {
        Button("Set Up…") { showingHelp = true }
            .buttonStyle(SoftButtonStyle())
            .sheet(isPresented: $showingHelp) { AccessibilityPermissionHelp() }
    }
}

struct AccessibilityPermissionHelp: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var installation = PermissionInstallation()
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Allow Airdraft to insert text").font(.system(size: 20, weight: .semibold))
                    Text(container.permissions.accessibilityGranted
                         ? "macOS now grants this running copy Accessibility access."
                         : "macOS has not granted this running copy access. An enabled switch for another copy or an older build does not confirm access for this one.")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(installation.name).font(.system(size: 13, weight: .semibold))
                        Text(installation.path).textSelection(.enabled)
                        Button("Show This Copy in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                        }.buttonStyle(.link)
                    }
                    .font(.system(size: 13))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))

                    if !installation.otherCopies.isEmpty {
                        Text("Another copy is running. Quit it before changing permissions:\n" + installation.otherCopies.joined(separator: "\n"))
                            .font(.system(size: 13)).foregroundStyle(.secondary).textSelection(.enabled)
                    }

                    if !container.permissions.accessibilityGranted {
                        Text("Open System Settings and enable this copy under Privacy & Security → Accessibility.")
                        Text("If its switch is already on").font(.system(size: 13, weight: .semibold))
                        Text("1. Quit every running copy of Airdraft.\n2. Turn off and remove the old Airdraft entries with the minus button.\n3. Add the copy you installed in Applications with the plus button, then enable it.\n4. Reopen that same copy of Airdraft.")
                            .font(.system(size: 13)).lineSpacing(4)
                        Text("If you opened Airdraft from the DMG, drag it into Applications and eject the DMG first. Removing an Accessibility entry does not delete your dictation history or settings.")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                        if installation.isAdHoc {
                            Text("This release uses ad-hoc signing. macOS may require these steps again after an update.")
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button(copied ? "Copied" : "Copy Diagnostics") {
                    installation = PermissionInstallation()
                    container.permissions.refresh()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(installation.report(trusted: container.permissions.accessibilityGranted), forType: .string)
                    copied = true
                }
                Button("Check Again") {
                    installation = PermissionInstallation()
                    container.permissions.refresh()
                }
                Spacer()
                if !container.permissions.accessibilityGranted {
                    Button("Open Settings…") { container.openAccessibilitySettings() }
                        .buttonStyle(.borderedProminent)
                }
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 620, height: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { container.permissions.refresh() }
    }
}

/// No TCC database access, permission resets, settings, or transcript collection.
private struct PermissionInstallation {
    let path = Bundle.main.bundlePath
    let identifier = Bundle.main.bundleIdentifier ?? "unknown"
    let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Airdraft"
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    let otherCopies: [String]
    let signing: String
    let isAdHoc: Bool

    init() {
        let ids = [AppIdentity.bundleID, AppIdentity.legacyBundleID, "com.lstudlo.app.airdraft.debug"]
        otherCopies = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && ids.contains($0.bundleIdentifier ?? "")
        }.compactMap { $0.bundleURL?.path }
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        if SecCodeCopySelf([], &code) == errSecSuccess, let code,
           SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
           SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
           let attributes = info as? [String: Any] {
            let flags = (attributes[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
            isAdHoc = flags & SecCodeSignatureFlags.adhoc.rawValue != 0
            if isAdHoc {
                signing = "Ad-hoc"
            } else if let certificates = attributes[kSecCodeInfoCertificates as String] as? [SecCertificate],
                      let leaf = certificates.first {
                signing = SecCertificateCopySubjectSummary(leaf) as String? ?? "Certificate signed"
            } else {
                signing = "Unknown"
            }
        } else {
            signing = "Unknown"
            isAdHoc = false
        }
    }

    func report(trusted: Bool) -> String {
        """
        Airdraft permission diagnostics
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        App: \(name) \(version) (\(build))
        Bundle ID: \(identifier)
        Running path: \(path)
        Signing: \(signing)
        AXIsProcessTrusted: \(trusted)
        Other running copies: \(otherCopies.isEmpty ? "none" : otherCopies.joined(separator: ", "))
        """
    }
}
