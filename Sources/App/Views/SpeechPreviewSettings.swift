import AirdraftCore
import SwiftUI

struct SpeechPreviewSettings: View {
    @Environment(AppContainer.self) private var container
    @State private var reason: String? = "Checking language assets…"
    @State private var refreshID = UUID()

    private var config: ASRConfig {
        ASRConfig(kind: .apple, appleLocale: container.settings.livePreviewLocale, language: "")
    }

    var body: some View {
        @Bindable var settings = container.settings
        let job = container.downloads.jobs[config.engineID]
        PageSection("Live preview") {
            SettingsCard {
                SettingRow(title: "Apple Speech language", subtitle: "Preview only") {
                    Picker("Preview language", selection: $settings.livePreviewLocale) {
                        ForEach(SpeechLanguage.appleLocales(including: settings.livePreviewLocale), id: \.code) {
                            Text($0.name).tag($0.code)
                        }
                    }.settingsPicker(width: 200)
                }
                RowDivider()
                SettingRow(title: "Language assets", subtitle: job?.error ?? reason ?? "Ready") {
                    if let progress = job?.progress {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(progress.currentFile).font(.caption).lineLimit(1)
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
            guard !RenderMode.isActive else { reason = "Language not installed"; return }
            let locale = settings.livePreviewLocale
            let unavailable = await SpeechPreview.unavailableReason(locale: locale)
            guard !Task.isCancelled, locale == settings.livePreviewLocale else { return }
            reason = unavailable
        }
    }
}
