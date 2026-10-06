import AirdraftCore
import SwiftUI

/// Shared preferences are checked against the model the active profile uses.
struct SpeechLanguageSettings: View {
    @Environment(AppContainer.self) private var container
    @State private var appleLocales: [String] = []
    /// Setup can preview a speech choice before it becomes the app default.
    var configuration: ASRConfig? = nil

    private var config: ASRConfig { configuration ?? container.speechConfig }
    private var capabilities: SpeechLanguageCapabilities { SpeechLanguagePolicy.capabilities(for: config) }
    private var selectedLanguage: String {
        // Display the model's accepted alias without rewriting the shared intent
        // when switching between e.g. Qwen's fil and Whisper's tl.
        if let resolved = try? SpeechLanguagePolicy.resolve(config),
           let language = resolved.language,
           capabilities.supportedLanguages?.contains(language) == true {
            return language
        }
        do { return try SpeechLanguagePolicy.canonicalLanguage(config.language) ?? "" }
        catch { return config.language }
    }
    private var issue: String? {
        do { _ = try SpeechLanguagePolicy.resolve(config); return nil }
        catch { return error.localizedDescription }
    }

    var body: some View {
        @Bindable var settings = container.settings
        if config.kind == .apple {
            SettingRow(title: "Apple Speech locale", subtitle: "Uses this fixed language for recognition.") {
                SoftPicker("Apple Speech locale", selection: Binding(
                    get: { config.effectiveAppleLocale },
                    set: { locale in
                        // This explicit choice updates the shared language intent;
                        // switching a model or profile never changes it.
                        settings.asr.appleLocale = locale
                        settings.asr.language = locale
                    }
                ), width: 200) {
                    ForEach(availableAppleLocales, id: \.self) { locale in
                        Text(Locale.current.localizedString(forIdentifier: locale) ?? locale).tag(locale)
                    }
                }
            }
            .task { appleLocales = await AppleSpeechTranscriber.supportedLocaleIdentifiers() }
        } else {
            SettingRow(title: "Language", subtitle: capabilities.summary) {
                SoftPicker("Language", selection: Binding(
                    get: { selectedLanguage },
                    set: { settings.asr.language = $0 }
                ), width: 200) {
                    if capabilities.supportsAutomatic != false {
                        Text("Detect Automatically").tag("")
                    } else if selectedLanguage.isEmpty {
                        Text("Choose Language").tag("").disabled(true)
                    }
                    ForEach(languageChoices, id: \.self) { code in
                        Text(SpeechLanguagePolicy.languageName(code)).tag(code)
                    }
                    if !selectedLanguage.isEmpty, !languageChoices.contains(selectedLanguage) {
                        // The full incompatibility and recovery action are below;
                        // keep the saved value readable inside the compact picker.
                        Text(SpeechLanguagePolicy.languageName(selectedLanguage))
                            .tag(selectedLanguage).disabled(true)
                    }
                }
            }
        }
        if let issue {
            Text(issue).supportingText()
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("speech-language-issue")
        }
        RowDivider()
        SettingRow(title: "Chinese script") {
            SoftSegmentedPicker("Chinese script", selection: $settings.asr.chineseScript,
                                options: ChineseScript.allCases.map { ($0, $0.title) }, width: 240)
        }
    }

    private var languageChoices: [String] {
        let common = ["en", "zh", "yue", "ja", "ko", "es", "fr", "de", "it", "pt", "ru", "vi", "th", "id"]
        var codes = capabilities.supportedLanguages ?? common
        if capabilities.supportedLanguages == nil, !selectedLanguage.isEmpty,
           !codes.contains(selectedLanguage) { codes.append(selectedLanguage) }
        return codes.sorted {
            SpeechLanguagePolicy.languageName($0).localizedStandardCompare(SpeechLanguagePolicy.languageName($1)) == .orderedAscending
        }
    }

    private var availableAppleLocales: [String] {
        Array(Set(appleLocales + [config.effectiveAppleLocale])).sorted()
    }
}
