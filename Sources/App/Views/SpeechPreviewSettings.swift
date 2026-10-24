import AirdraftCore
import SwiftUI

struct SpeechPreviewSettings: View {
    @Environment(AppContainer.self) private var container
    @State private var reason: String? = String(localized: "Checking language assets…")
    @State private var refreshID = UUID()
    @State private var appleLocales: [String] = []

    private var config: ASRConfig {
        ASRConfig(kind: .apple, appleLocale: container.settings.livePreviewLocale, language: "")
    }

    var body: some View {
        @Bindable var settings = container.settings
        let job = container.downloads.jobs[config.engineID]
        PageSection("Live preview") {
            SettingsCard {
                SettingRow(title: "Apple Speech language", subtitle: "Preview only") {
                    SoftPicker("Preview language", selection: $settings.livePreviewLocale, width: 200) {
                        ForEach(SpeechLanguage.appleLocales(supported: appleLocales, including: settings.livePreviewLocale), id: \.self) {
                            Text(SpeechLanguage.name($0)).tag($0)
                        }
                    }
                }
                .task { appleLocales = await AppleSpeechTranscriber.supportedLocaleIdentifiers() }
                RowDivider()
                SettingRow(title: "Language assets", detail: job?.error ?? reason ?? String(localized: "Ready")) {
                    if let progress = job?.progress {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(progress.currentFile).appFont(.caption2).lineLimit(1)
                            Button("Cancel") { container.downloads.cancel(config) }
                                .buttonStyle(SoftButtonStyle()).disabled(job?.cancelling == true)
                        }
                    } else if reason != nil && AppleSpeechTranscriber.isAvailable {
                        Button("Install Language") {
                            container.downloads.start(config) { refreshID = UUID() }
                        }.buttonStyle(SoftButtonStyle())
                    } else {
                        StatusDot(ok: reason == nil)
                    }
                }
            }
        }
        .task(id: "\(settings.livePreviewLocale)|\(refreshID)") {
            guard !RenderMode.isActive else { reason = String(localized: "Language not installed"); return }
            let locale = settings.livePreviewLocale
            let unavailable = await SpeechPreview.unavailableReason(locale: locale)
            guard !Task.isCancelled, locale == settings.livePreviewLocale else { return }
            reason = unavailable
        }
    }
}
