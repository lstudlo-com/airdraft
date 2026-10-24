import Foundation

/// The spoken sample Settings' refinement Test sends: a messy sentence with
/// fillers and a spoken list, in the language the user dictates, so the result
/// can be read. Languages without a sample use English.
public enum RefinementSample {
    public static func transcript(for config: ASRConfig, preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        let selected = config.kind == .apple ? config.effectiveAppleLocale : config.language
        let explicit = (try? SpeechLanguagePolicy.canonicalLanguage(selected)) ?? nil
        let language = explicit ?? preferredLanguages.lazy.compactMap { (try? SpeechLanguagePolicy.canonicalLanguage($0)) ?? nil }.first
        switch language {
        case "zh", "yue", "zh-hk":
            return config.effectiveChineseScript == .simplified
                ? "嗯 这是一个 测试 就是说 我们今天要 第一 买牛奶 第二 写程序"
                : "嗯 這是一個 測試 就是說 我們今天要 第一 買牛奶 第二 寫程式"
        case "ja": return "えーと これは テストです あの 今日は まず 牛乳を買って 次に コードを書きます"
        case "es": return "eh bueno esto es una prueba este hoy tenemos que primero comprar leche segundo escribir código"
        default: return "um so this is a test uh today we need to first buy milk second write some code"
        }
    }
}
