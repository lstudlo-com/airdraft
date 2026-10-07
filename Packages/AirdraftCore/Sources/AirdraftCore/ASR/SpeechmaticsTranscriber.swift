import Foundation

public struct SpeechmaticsTranscriber: Transcriber {
    public let id = "speechmatics:enhanced"
    public let apiKey: String?
    public let timeout: TimeInterval
    private let http: TranscriptionHTTP
    private let pollInterval: TimeInterval
    private static let base = URL(string: "https://eu1.asr.api.speechmatics.com/v2")!

    public init(apiKey: String?, timeout: TimeInterval = 180, session: URLSession = .shared, pollInterval: TimeInterval = 0.5) {
        self.apiKey = apiKey; self.timeout = timeout; http = TranscriptionHTTP(session: session)
        self.pollInterval = pollInterval
    }

    public func prepare() async throws {}

    func payload(hints: TranscriptionHints) throws -> [String: Any] {
        let language = try SpeechLanguagePolicy.resolve(ASRConfig(kind: .speechmatics, language: hints.languageCode ?? "auto")).language
        var config: [String: Any] = ["model": "enhanced", "language": language == "zh" ? "cmn" : language ?? "auto"]
        let terms = hints.vocabularyTerms.prefix(100).map { ["content": String($0.prefix(100))] }
        if !terms.isEmpty { config["additional_vocab"] = terms }
        return ["type": "transcription", "transcription_config": config]
    }

    public func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        try Task.checkCancellation()
        guard !samples.isEmpty else { throw TranscriberError.emptyAudio }
        let key = try TranscriptionHTTP.requireKey(apiKey, provider: "Speechmatics")
        let config = try JSONSerialization.data(withJSONObject: payload(hints: hints))
        let started = Date(), deadline = Date().addingTimeInterval(timeout)
        var jobID: String?
        do {
            struct Created: Decodable { let id: String }
            let form = MultipartForm()
            var create = try CloudSpeechResources.request(Self.base.appendingPathComponent("jobs"), method: "POST", key: key, deadline: deadline)
            create.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
            create.httpBody = form.body(fields: [("config", String(decoding: config, as: UTF8.self))],
                                        wav: WAVEncoder.encode(samples: samples), fileField: "data_file", jsonFields: ["config"])
            let created = try await http.decode(Created.self, from: create)
            guard CloudSpeechResources.isResourceID(created.id) else { throw TranscriberError.invalidResponse }
            jobID = created.id
            struct Details: Decodable {
                struct Job: Decodable { let id: String; let status: String }
                let job: Job
            }
            while true {
                let poll = try CloudSpeechResources.request(Self.base.appendingPathComponent("jobs/\(created.id)"), key: key, deadline: deadline)
                let job = try await http.decode(Details.self, from: poll).job
                guard job.id == created.id else { throw TranscriberError.invalidResponse }
                if job.status == "done" { break }
                if ["rejected", "deleted", "expired"].contains(job.status) {
                    throw TranscriberError.providerFailure("Speechmatics", "The transcription job was \(job.status).")
                }
                guard ["running", "queued"].contains(job.status) else { throw TranscriberError.invalidResponse }
                try await CloudSpeechResources.pause(interval: pollInterval, deadline: deadline)
            }
            var components = URLComponents(url: Self.base.appendingPathComponent("jobs/\(created.id)/transcript"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "format", value: "txt")]
            let fetch = try CloudSpeechResources.request(components.url!, key: key, deadline: deadline)
            let data = try await http.send(fetch)
            guard let text = String(data: data, encoding: .utf8) else { throw TranscriberError.invalidResponse }
            await cleanup(jobID, key: key)
            jobID = nil
            try Task.checkCancellation()
            return Transcript(text: text.trimmingCharacters(in: .whitespacesAndNewlines), language: hints.isoLanguage,
                              engine: id, latencyMs: Int(Date().timeIntervalSince(started) * 1000))
        } catch {
            await cleanup(jobID, key: key)
            throw error
        }
    }

    private func cleanup(_ jobID: String?, key: String) async {
        guard let jobID, CloudSpeechResources.isResourceID(jobID) else { return }
        var components = URLComponents(url: Self.base.appendingPathComponent("jobs/\(jobID)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "force", value: "true")]
        await CloudSpeechResources.delete(components.url, key: key, http: http)
    }
}
