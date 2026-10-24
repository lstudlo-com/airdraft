import AVFoundation
import Foundation
import Speech

/// macOS 26 SpeechAnalyzer. No download of our own: Apple installs the
/// language asset on first use. Fast, on the Neural Engine, supports zh_TW.
public actor AppleSpeechTranscriber: Transcriber {
    public nonisolated let id: String
    private let localeIdentifier: String

    public init(locale: String) {
        self.localeIdentifier = locale
        self.id = "apple-speech:\(locale)"
    }

    public static var isAvailable: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    /// Query the OS rather than claiming a static list applies to every Mac.
    public static func supportedLocaleIdentifiers() async -> [String] {
        guard #available(macOS 26, *) else { return [] }
        return await SpeechTranscriber.supportedLocales.map(\.identifier).sorted()
    }

    /// The supported locale for an identifier: the OS equivalent, otherwise a
    /// supported locale of the same language, preferring the requested region and
    /// then the Mac's formatting region (a new setup's fr-BE or en-TW still finds
    /// French or English). Chinese never crosses scripts or into Cantonese here:
    /// its locales name the script the user chose.
    @available(macOS 26, *)
    static func resolvedLocale(for identifier: String,
                               region: String? = Locale.current.region?.identifier) async -> Locale? {
        let requested = Locale(identifier: identifier)
        if let equivalent = await SpeechTranscriber.supportedLocale(equivalentTo: requested) { return equivalent }
        guard let language = requested.language.languageCode?.identifier, language != "zh", language != "yue" else { return nil }
        let candidates = await SpeechTranscriber.supportedLocales
            .filter { $0.language.languageCode?.identifier == language }
            .sorted { $0.identifier < $1.identifier }
        // Then the language's own region: English in Taiwan resolves to en-US, not
        // to the alphabetically first English locale.
        let likely = Locale.Language(identifier: language).maximalIdentifier.split(separator: "-").last.map(String.init)
        let preferredRegions = [requested.region?.identifier, region, likely].compactMap { $0 }
        for preferred in preferredRegions {
            if let match = candidates.first(where: { $0.region?.identifier == preferred }) { return match }
        }
        return candidates.first
    }

    public func isReady() async -> Bool {
        guard #available(macOS 26, *) else { return false }
        guard let locale = await Self.resolvedLocale(for: localeIdentifier) else { return false }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        return await AssetInventory.status(forModules: [transcriber]) == .installed
    }

    public func prepare() async throws {
        guard #available(macOS 26, *) else { throw TranscriberError.appleUnavailable }
        let locale = try await supportedLocale()
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    public func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        try Task.checkCancellation()
        guard !samples.isEmpty else { throw TranscriberError.emptyAudio }
        guard #available(macOS 26, *) else { throw TranscriberError.appleUnavailable }
        let started = Date()
        let locale = try await supportedLocale()
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
            throw TranscriberError.providerFailure("Apple Speech", String(localized: "Language assets are not installed. Open Models and load Apple Speech before retrying.", bundle: .module))
        }
        try Task.checkCancellation()
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        guard let sourceFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw TranscriberError.invalidResponse
        }
        sourceBuffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            sourceBuffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) ?? sourceFormat
        try Task.checkCancellation()
        let buffer = try Self.convert(sourceBuffer, to: targetFormat)

        let collector = Task<String, Error> {
            var text = ""
            for try await result in transcriber.results {
                text += String(result.text.characters)
            }
            return text
        }
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        continuation.yield(AnalyzerInput(buffer: buffer))
        continuation.finish()
        defer { collector.cancel() }
        let text = try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                _ = try await analyzer.analyzeSequence(stream)
                // A cancelled input sequence may return normally. Do not wait
                // for final results from an analysis that has already stopped.
                try Task.checkCancellation()
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                try Task.checkCancellation()
                let result = try await collector.value
                try Task.checkCancellation()
                return result.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                collector.cancel()
                await analyzer.cancelAndFinishNow()
                if Task.isCancelled { throw CancellationError() }
                throw error
            }
        } onCancel: {
            collector.cancel()
            Task { await analyzer.cancelAndFinishNow() }
        }
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        return Transcript(text: text, language: locale.identifier, engine: id, latencyMs: ms)
    }

    /// The Apple Speech locale for a selected speech language. A bare language
    /// takes the Mac's formatting region when the language has a locale there:
    /// en-GB, en-IN, pt-PT, es-MX, fr-CA. English uses a region only where it is
    /// a first or official language (the system knows an en_TW locale for
    /// formatting), so English on a Taiwan Mac stays en-US. Other bare languages
    /// pass through and the OS resolves them (`resolvedLocale`).
    static func locale(forLanguage code: String, region: String? = Locale.current.region?.identifier) -> String? {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: "-")
        let lowered = normalized.lowercased()
        let country = region.map { $0.uppercased() }.flatMap { $0.count == 2 && $0.allSatisfy({ $0.isASCII && $0.isLetter }) ? $0 : nil }
        switch lowered {
        case "", "auto": return nil
        case "zh": return "zh-TW"
        case "ja": return "ja-JP"
        case "ko": return "ko-KR"
        case "en":
            return country.map { englishRegions.contains($0) ? "en-\($0)" : "en-US" } ?? "en-US"
        default:
            // Preserve all other language/locale requests. The OS resolves supported
            // equivalents below; French must never fall back to a saved Chinese locale.
            if lowered.range(of: "^[a-z]{2,3}$", options: .regularExpression) != nil, let country,
               regionalLocales.contains("\(lowered)_\(country)") {
                return "\(lowered)-\(country)"
            }
            return normalized
        }
    }

    /// Regions whose English Apple Speech can have its own locale.
    static let englishRegions: Set<String> = ["US", "GB", "AU", "CA", "IE", "IN", "NZ", "SG", "ZA", "PH"]

    /// CLDR locales (language_REGION) the system knows, such as en_GB and pt_BR.
    private static let regionalLocales = Set(Locale.availableIdentifiers)

    @available(macOS 26, *)
    private func supportedLocale() async throws -> Locale {
        guard let locale = await Self.resolvedLocale(for: localeIdentifier) else {
            throw TranscriberError.providerFailure("Apple Speech", String(localized: "\(localeIdentifier) is unavailable on this Mac. Choose a supported locale in Models.", bundle: .module))
        }
        return locale
    }

    private static func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        if buffer.format == format { return buffer }
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { throw TranscriberError.invalidResponse }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { throw TranscriberError.invalidResponse }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed { status.pointee = .endOfStream; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        if let error { throw error }
        return out
    }
}
