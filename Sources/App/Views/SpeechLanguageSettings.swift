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
                ), width: SoftPickerWidth.fitting(appleLocaleChoices.map(SpeechLanguage.name), minimum: 200, maximum: 320)) {
                    ForEach(appleLocaleChoices, id: \.self) { locale in
                        Text(SpeechLanguage.name(locale)).tag(locale)
                    }
                }
            }
            .task { appleLocales = await AppleSpeechTranscriber.supportedLocaleIdentifiers() }
        } else {
            SettingRow(title: "Language", detail: capabilities.summary) {
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
                        Text(SpeechLanguagePolicy.languageLabel(code)).tag(code)
                    }
                    if !selectedLanguage.isEmpty, !languageChoices.contains(selectedLanguage) {
                        // The full incompatibility and recovery action are below;
                        // keep the saved value readable inside the compact picker.
                        Text(SpeechLanguagePolicy.languageLabel(selectedLanguage))
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
        if showsChineseScript {
            RowDivider()
            SettingRow(title: "Chinese script") {
                SoftSegmentedPicker("Chinese script", selection: $settings.asr.chineseScript,
                                    options: ChineseScript.allCases.map { ($0, $0.title) }, width: 240)
            }
        }
    }

    /// The script only matters when this setup can write Chinese: Mandarin or
    /// Cantonese selected, or Auto for someone who speaks Chinese or already
    /// chose a script. Other languages never see a Chinese-only setting.
    private var showsChineseScript: Bool {
        let language = config.kind == .apple ? config.effectiveAppleLocale : config.language
        guard ChineseScript.applies(toSpeechLanguage: language) else { return false }
        if !language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return config.chineseScript != .auto
            || Locale.preferredLanguages.contains { Locale.Language(identifier: $0).languageCode?.identifier == "zh" }
    }

    private var appleLocaleChoices: [String] {
        SpeechLanguage.appleLocales(supported: appleLocales, including: config.effectiveAppleLocale)
    }

    private var languageChoices: [String] {
        var codes = capabilities.supportedLanguages ?? SpeechLanguagePolicy.commonLanguages()
        if capabilities.supportedLanguages == nil, !selectedLanguage.isEmpty,
           !codes.contains(selectedLanguage) { codes.append(selectedLanguage) }
        return codes.sorted {
            SpeechLanguagePolicy.languageLabel($0).localizedStandardCompare(SpeechLanguagePolicy.languageLabel($1)) == .orderedAscending
        }
    }
}
