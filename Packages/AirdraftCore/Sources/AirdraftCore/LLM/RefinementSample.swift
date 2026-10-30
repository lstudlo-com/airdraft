import Foundation

/// The spoken sample Settings' refinement Test sends: a messy sentence with
/// fillers and a spoken list, in the language the user dictates, so the result
/// can be read. Languages without a sample use English.
public enum RefinementSample {
    public static func transcript(for config: ASRConfig, preferredLanguages: [String] = SystemLanguages.preferred) -> String {
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
        case "ko": return "음 그러니까 이건 테스트예요 어 오늘은 첫째 우유 사기 둘째 코드 작성하기"
        case "fr": return "euh bon alors c'est un test du coup aujourd'hui on doit premièrement acheter du lait deuxièmement écrire du code"
        case "de": return "ähm also das ist ein Test äh heute müssen wir erstens Milch kaufen zweitens Code schreiben"
        case "pt": return "hum então isso é um teste tipo hoje a gente precisa primeiro comprar leite segundo escrever código"
        case "it": return "ehm allora questo è un test cioè oggi dobbiamo primo comprare il latte secondo scrivere codice"
        case "ru": return "эм ну это тест короче сегодня нам нужно во-первых купить молоко во-вторых написать код"
        case "ar": return "اممم يعني هذا اختبار يعني اليوم لازم أولاً نشتري حليب ثانياً نكتب كود"
        case "hi": return "अम्म तो यह एक टेस्ट है मतलब आज हमें पहला दूध खरीदना है दूसरा कोड लिखना है"
        case "id": return "eh jadi ini tes ya hari ini kita harus pertama beli susu kedua menulis kode"
        default: return "um so this is a test uh today we need to first buy milk second write some code"
        }
    }
}
