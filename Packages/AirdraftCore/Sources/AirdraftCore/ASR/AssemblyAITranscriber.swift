import Foundation

/// Batch transcription supports Airdraft's full recording length without chunking.
public struct AssemblyAITranscriber: Transcriber {
    public let id = "assemblyAI:universal-3-5-pro"
    public let apiKey: String?
    public let timeout: TimeInterval
    private let http: TranscriptionHTTP
    private let pollInterval: TimeInterval
    private static let base = URL(string: "https://api.assemblyai.com/v2")!

    public init(apiKey: String?, timeout: TimeInterval = 180, session: URLSession = .shared, pollInterval: TimeInterval = 0.5) {
        self.apiKey = apiKey; self.timeout = timeout; http = TranscriptionHTTP(session: session)
        self.pollInterval = pollInterval
    }

    public func prepare() async throws {}

    func payload(audioURL: String, hints: TranscriptionHints) throws -> [String: Any] {
        let language = try SpeechLanguagePolicy.resolve(ASRConfig(kind: .assemblyAI, language: hints.languageCode ?? "auto")).language
        let expected = language.map { Array(Set([$0, "en"])).sorted() } ?? SpeechLanguagePolicy.assemblyLanguages
        var body: [String: Any] = ["audio_url": audioURL, "speech_models": ["universal-3-5-pro"],
                                   "language_detection": true,
                                   "language_detection_options": ["expected_languages": expected, "code_switching": true]]
        let terms = hints.vocabularyTerms.prefix(100).filter { $0.split(whereSeparator: \.isWhitespace).count <= 6 }
        if !terms.isEmpty { body["keyterms_prompt"] = Array(terms) }
        return body
    }

    public func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        try Task.checkCancellation()
        guard !samples.isEmpty else { throw TranscriberError.emptyAudio }
        let key = try TranscriptionHTTP.requireKey(apiKey, provider: "AssemblyAI")
        // Validate language before uploading audio.
        _ = try payload(audioURL: "", hints: hints)
        let started = Date(), deadline = Date().addingTimeInterval(timeout)
        var jobID: String?
        do {
            struct Upload: Decodable { let upload_url: String }
            var upload = try CloudSpeechResources.request(Self.base.appendingPathComponent("upload"), method: "POST", key: key, prefix: "", deadline: deadline)
            upload.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            upload.httpBody = WAVEncoder.encode(samples: samples)
            let audio = try await http.decode(Upload.self, from: upload).upload_url
            guard let url = URL(string: audio), url.scheme == "https", url.host != nil else { throw TranscriberError.invalidResponse }
            struct Job: Decodable { let id: String; let status: String; let text: String?; let language_code: String?; let error: String? }
            var create = try CloudSpeechResources.request(Self.base.appendingPathComponent("transcript"), method: "POST", key: key, prefix: "", deadline: deadline)
            create.setValue("application/json", forHTTPHeaderField: "Content-Type")
            create.httpBody = try JSONSerialization.data(withJSONObject: payload(audioURL: audio, hints: hints))
            var job = try await http.decode(Job.self, from: create)
            guard UUID(uuidString: job.id) != nil else { throw TranscriberError.invalidResponse }
            jobID = job.id
            while job.status != "completed" {
                if job.status == "error" { throw TranscriberError.providerFailure("AssemblyAI", job.error ?? "Transcription failed.") }
                guard ["queued", "processing"].contains(job.status) else { throw TranscriberError.invalidResponse }
                try await CloudSpeechResources.pause(interval: pollInterval, deadline: deadline)
                let poll = try CloudSpeechResources.request(Self.base.appendingPathComponent("transcript/\(job.id)"), key: key, prefix: "", deadline: deadline)
                let next = try await http.decode(Job.self, from: poll)
                guard next.id == job.id else { throw TranscriberError.invalidResponse }
                job = next
            }
            guard let text = job.text else { throw TranscriberError.invalidResponse }
            await cleanup(jobID, key: key)
            jobID = nil
            try Task.checkCancellation()
            return Transcript(text: text.trimmingCharacters(in: .whitespacesAndNewlines), language: job.language_code ?? hints.isoLanguage,
                              engine: id, latencyMs: Int(Date().timeIntervalSince(started) * 1000))
        } catch {
            await cleanup(jobID, key: key)
            throw error
        }
    }

    private func cleanup(_ jobID: String?, key: String) async {
        let url = jobID.flatMap { UUID(uuidString: $0) != nil ? Self.base.appendingPathComponent("transcript/\($0)") : nil }
        await CloudSpeechResources.delete(url, key: key, prefix: "", http: http)
    }
}
