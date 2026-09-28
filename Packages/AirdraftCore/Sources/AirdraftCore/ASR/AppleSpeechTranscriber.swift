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

    public func isReady() async -> Bool {
        guard #available(macOS 26, *) else { return false }
        let transcriber = SpeechTranscriber(locale: Locale(identifier: localeIdentifier), preset: .transcription)
        return await AssetInventory.status(forModules: [transcriber]) == .installed
    }

    public func prepare() async throws {
        guard #available(macOS 26, *) else { throw TranscriberError.appleUnavailable }
        let transcriber = SpeechTranscriber(locale: Locale(identifier: localeIdentifier), preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    public func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        try Task.checkCancellation()
        guard !samples.isEmpty else { throw TranscriberError.emptyAudio }
        guard #available(macOS 26, *) else { throw TranscriberError.appleUnavailable }
        let started = Date()
        let transcriber = SpeechTranscriber(locale: Locale(identifier: localeIdentifier), preset: .transcription)
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
            throw TranscriberError.providerFailure("Apple Speech", "Language assets are not installed. Open Models and load Apple Speech before retrying.")
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
        return Transcript(text: text, language: hints.language, engine: id, latencyMs: ms)
    }

    static func locale(forLanguage code: String) -> String? {
        switch code.lowercased() {
        case "zh": return "zh-TW"
        case "en": return "en-US"
        case "ja": return "ja-JP"
        case "ko": return "ko-KR"
        default: return nil
        }
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
