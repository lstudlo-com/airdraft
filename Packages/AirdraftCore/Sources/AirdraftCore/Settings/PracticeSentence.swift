import Foundation

/// The sentence onboarding's Try It asks the user to read aloud. It follows the
/// language the speech setup will recognize, not only the interface language:
/// someone with an English interface who dictates Spanish reads Spanish, and a
/// model that cannot recognize the interface language gets one it can.
/// Sentences are data in the speech language, not interface copy, so they are
/// not localized; the interface catalog's translation is used whenever the
/// spoken language is the interface language.
public enum PracticeSentence {
    /// Each says: "Hello! I'm trying Airdraft for the first time, and it's writing what I say."
    static let sentences: [String: String] = [
        "en": "Hello! I’m trying Airdraft for the first time, and it’s writing what I say.",
        "zh-Hant": "哈囉！我第一次試用 Airdraft，它正在寫下我說的話。",
        "zh-Hans": "你好！我第一次试用 Airdraft，它正在写下我说的话。",
        "ja": "こんにちは。Airdraft を初めて試しています。話したことが文字になっています。",
        "ko": "안녕하세요! Airdraft를 처음 써 보고 있는데, 제가 말하는 내용을 받아 적고 있어요.",
        "es": "¡Hola! Estoy probando Airdraft por primera vez y está escribiendo lo que digo.",
        "fr": "Bonjour ! J’essaie Airdraft pour la première fois, et il écrit ce que je dis.",
        "de": "Hallo! Ich probiere Airdraft zum ersten Mal aus, und es schreibt auf, was ich sage.",
        "pt": "Olá! Estou experimentando o Airdraft pela primeira vez, e ele está escrevendo o que eu digo.",
        "it": "Ciao! Sto provando Airdraft per la prima volta e sta scrivendo quello che dico.",
        "nl": "Hallo! Ik probeer Airdraft voor het eerst uit en het schrijft op wat ik zeg.",
        "ru": "Здравствуйте! Я впервые пробую Airdraft, и он записывает то, что я говорю.",
        "uk": "Привіт! Я вперше пробую Airdraft, і він записує те, що я кажу.",
        "ar": "مرحبًا! أجرّب Airdraft لأول مرة، وهو يكتب ما أقوله.",
        "hi": "नमस्ते! यह Airdraft के साथ मेरा पहला प्रयास है, और यह मेरी कही हुई बातें लिख रहा है।",
        "id": "Halo! Saya sedang mencoba Airdraft untuk pertama kali, dan ia menulis apa yang saya katakan.",
        "tr": "Merhaba! Airdraft’ı ilk kez deniyorum ve söylediklerimi yazıyor.",
        "vi": "Xin chào! Tôi đang thử Airdraft lần đầu tiên, và nó đang viết lại những gì tôi nói.",
    ]

    /// - Parameters:
    ///   - interfaceLanguage: the localization the interface is shown in
    ///     (`Bundle.main.preferredLocalizations.first`).
    ///   - localized: the interface catalog's sentence in that language.
    public static func sentence(for config: ASRConfig, interfaceLanguage: String, localized: String,
                                preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        let interface = family(canonical(interfaceLanguage) ?? "en")
        let spoken = spokenLanguage(for: config, interface: interface, preferredLanguages: preferredLanguages)
        if family(spoken) == interface { return localized }
        if family(spoken) == "zh" {
            let simplified = config.effectiveChineseScript == .simplified
                || (config.effectiveChineseScript == .auto && ChineseScript.systemDefault(preferredLanguages: preferredLanguages) == .simplified)
            return sentences[simplified ? "zh-Hans" : "zh-Hant"]!
        }
        return sentences[spoken] ?? localized
    }

    /// The selected speech language (Apple Speech: its locale's language). Under
    /// Auto: the interface language when the model recognizes it, otherwise the
    /// first of the user's languages it recognizes, then English, then its first.
    static func spokenLanguage(for config: ASRConfig, interface: String, preferredLanguages: [String]) -> String {
        let selected = config.kind == .apple ? config.effectiveAppleLocale : config.language
        if let explicit = canonical(selected) { return explicit }
        guard let supported = SpeechLanguagePolicy.capabilities(for: config).supportedLanguages, !supported.isEmpty else {
            return interface
        }
        let recognizes = { (code: String) in supported.contains(code) || (family(code) == "zh" && supported.contains("zh")) }
        if recognizes(interface) { return interface }
        if let preferred = preferredLanguages.lazy.compactMap(canonical).first(where: recognizes) { return preferred }
        return supported.contains("en") ? "en" : supported[0]
    }

    static func canonical(_ identifier: String) -> String? {
        (try? SpeechLanguagePolicy.canonicalLanguage(identifier)) ?? nil
    }

    /// Mandarin, Cantonese and Hong Kong Chinese read the same written sentence.
    static func family(_ code: String) -> String {
        ["zh", "yue", "zh-hk"].contains(code) ? "zh" : code
    }
}
