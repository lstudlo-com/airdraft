import XCTest
@testable import AirdraftCore

/// AD-098: languages other than Chinese and English get their own defaults,
/// word counts, script handling and refinement checks.
@MainActor
final class InternationalDefaultsTests: XCTestCase {
    // MARK: - New setup defaults

    func testAppleSpeechLocaleFollowsTheFirstLanguageWithoutChinese() {
        XCTAssertEqual(ASRConfig.systemAppleLocale(preferredLanguages: ["fr-FR", "en-US"], region: "FR"), "fr-FR")
        XCTAssertEqual(ASRConfig.systemAppleLocale(preferredLanguages: ["ja-JP"], region: "JP"), "ja-JP")
        // es-419 is a region group: the Mac's region names the country.
        XCTAssertEqual(ASRConfig.systemAppleLocale(preferredLanguages: ["es-419"], region: "MX"), "es-MX")
        XCTAssertEqual(ASRConfig.systemAppleLocale(preferredLanguages: ["es-419"], region: nil), "es")
        XCTAssertEqual(ASRConfig.systemAppleLocale(preferredLanguages: ["de"], region: "AT"), "de-AT")
        XCTAssertEqual(ASRConfig.systemAppleLocale(preferredLanguages: [], region: "US"), "en-US")
        // A Chinese language anywhere keeps the Mandarin locale in its script.
        XCTAssertEqual(ASRConfig.systemAppleLocale(preferredLanguages: ["zh-Hans-CN"], region: "CN"), "zh-CN")
        XCTAssertEqual(ASRConfig.systemAppleLocale(preferredLanguages: ["en-US", "zh-Hant-TW"], region: "TW"), "zh-TW")
    }

    func testNewSetupOnASpanishMacHasNoChineseDefaults() throws {
        let suite = "InternationalDefaultsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, preferredLanguages: ["es-ES"])
        XCTAssertEqual(settings.asr.chineseScript, .auto)
        XCTAssertEqual(settings.asr.appleLocale, "es-ES")
        XCTAssertEqual(settings.livePreviewLocale, "es-ES")
        XCTAssertEqual(settings.asr.effectiveChineseScript, .auto)
    }

    func testAppleSpeechUsesItsLocaleForTheChineseScript() {
        var apple = ASRConfig(kind: .apple, appleLocale: "fr-FR", language: "", chineseScript: .traditional)
        XCTAssertEqual(apple.effectiveChineseScript, .auto)
        apple.appleLocale = "zh-TW"
        XCTAssertEqual(apple.effectiveChineseScript, .traditional)
    }

    func testCommonLanguagesPutTheUsersLanguagesFirst() {
        let codes = SpeechLanguagePolicy.commonLanguages(preferred: ["es-MX", "en-US", "zh-Hant-TW"])
        XCTAssertEqual(Array(codes.prefix(3)), ["es", "en", "zh"])
        XCTAssertEqual(codes.count, Set(codes).count)
        XCTAssertTrue(codes.contains("hi") && codes.contains("ar") && codes.contains("ja"))
    }

    // MARK: - Word counts

    func testWordCountsAcrossScripts() {
        XCTAssertEqual(DictationPipeline.approximateWordCount("hello world"), 2)
        XCTAssertEqual(DictationPipeline.approximateWordCount("今天很好"), 4)
        XCTAssertEqual(DictationPipeline.approximateWordCount("今日はいい天気"), 7)
        // Korean separates words with spaces.
        XCTAssertEqual(DictationPipeline.approximateWordCount("안녕하세요 반갑습니다"), 2)
        // Devanagari virama and Arabic marks stay inside their words.
        XCTAssertEqual(DictationPipeline.approximateWordCount("मुझे कल रिपोर्ट भेजनी है"), 5)
        XCTAssertEqual(DictationPipeline.approximateWordCount("أرسل التقرير غدًا"), 3)
        XCTAssertEqual(DictationPipeline.approximateWordCount("¿Puedes enviar el informe mañana?"), 5)
    }

    func testThaiSentenceIsNotOneWordBelowTheRefinementThreshold() {
        // No spaces: before AD-098 this counted as one word and skipped refinement.
        XCTAssertGreaterThanOrEqual(DictationPipeline.approximateWordCount("พรุ่งนี้ช่วยส่งรายงานให้ฉันด้วย"), 3)
    }

    func testThaiWindowsJoinWithoutASpace() {
        XCTAssertEqual(AudioChunker.join(["พรุ่งนี้ช่วย", "ส่งรายงาน"]), "พรุ่งนี้ช่วยส่งรายงาน")
        XCTAssertEqual(AudioChunker.join(["hola", "mundo"]), "hola mundo")
    }

    // MARK: - Hallucinations

    func testKnownHallucinationsInOtherLanguages() {
        for phrase in ["¡Gracias por ver el video!", "Subtítulos realizados por la comunidad de Amara.org",
                       "ご視聴ありがとうございました。", "Продолжение следует...", "시청해 주셔서 감사합니다."] {
            XCTAssertTrue(KnownHallucination.matches(phrase), phrase)
        }
        XCTAssertFalse(KnownHallucination.matches("Gracias por ver el informe, lo reviso mañana."))
    }

    // MARK: - Refinement test sample

    func testRefinementSampleFollowsTheSpeechLanguage() {
        XCTAssertTrue(RefinementSample.transcript(for: ASRConfig(language: "es")).contains("prueba"))
        XCTAssertTrue(RefinementSample.transcript(for: ASRConfig(language: "ja")).contains("テスト"))
        XCTAssertTrue(RefinementSample.transcript(for: ASRConfig(language: "zh", chineseScript: .simplified)).contains("测试"))
        XCTAssertTrue(RefinementSample.transcript(for: ASRConfig(language: "zh", chineseScript: .traditional)).contains("測試"))
        XCTAssertTrue(RefinementSample.transcript(for: ASRConfig(language: ""), preferredLanguages: ["fr-FR"]).contains("test"))
        XCTAssertTrue(RefinementSample.transcript(for: ASRConfig(language: ""), preferredLanguages: ["es-MX"]).contains("prueba"))
    }

    // MARK: - Apple Intelligence languages

    func testAppleIntelligenceNamesAnUnsupportedSpeechLanguage() {
        let supported: Set<String> = ["en", "es", "ja", "zh", "fr"]
        func name(_ language: String, preferred: [String] = ["en-US"]) -> String? {
            AppleIntelligenceRefiner.unsupportedLanguageName(for: ASRConfig(language: language),
                                                             preferredLanguages: preferred, supported: supported)
        }
        XCTAssertNil(name("es"))
        XCTAssertNil(name("ja"))
        XCTAssertNil(name("yue"), "Cantonese is written in Chinese characters")
        XCTAssertEqual(name("hi"), SpeechLanguagePolicy.languageName("hi"))
        XCTAssertEqual(name("", preferred: ["id-ID", "en-US"]), SpeechLanguagePolicy.languageName("id"))
        XCTAssertNil(name("", preferred: ["es-MX"]))
        XCTAssertNil(AppleIntelligenceRefiner.unsupportedLanguageName(for: ASRConfig(language: "hi"),
                                                                      preferredLanguages: [], supported: []))
    }
}
