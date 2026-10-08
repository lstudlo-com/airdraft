import Foundation

/// Dedicated transcription model, using Files and the current Interactions schema.
public struct GeminiTranscriber: Transcriber {
    public let id = "gemini:gemini-3.5-transcribe"
    public let apiKey: String?
    public let timeout: TimeInterval
    private let http: TranscriptionHTTP
    private let pollInterval: TimeInterval
    private static let host = "generativelanguage.googleapis.com"
    private static let base = URL(string: "https://generativelanguage.googleapis.com")!

    public init(apiKey: String?, timeout: TimeInterval = 180, session: URLSession? = nil, pollInterval: TimeInterval = 0.5) {
        self.apiKey = apiKey; self.timeout = timeout; http = TranscriptionHTTP(session: session)
        self.pollInterval = pollInterval
    }

    public func prepare() async throws {}

    func payload(fileURI: String, hints: TranscriptionHints) throws -> [String: Any] {
        let language = try SpeechLanguagePolicy.resolve(ASRConfig(kind: .gemini, language: hints.languageCode ?? "auto")).language
        var config: [String: Any] = ["mode": ["type": "verbatim"], "language_codes": language.map { [$0] } ?? []]
        let terms = Array(hints.vocabularyTerms.prefix(100))
        if !terms.isEmpty { config["custom_vocabulary"] = terms }
        return ["model": "gemini-3.5-transcribe", "store": false,
                "input": [["type": "audio", "uri": fileURI, "mime_type": "audio/wav"]],
                "generation_config": ["transcription_config": config]]
    }

    public func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        try Task.checkCancellation()
        guard !samples.isEmpty else { throw TranscriberError.emptyAudio }
        let key = try TranscriptionHTTP.requireKey(apiKey, provider: "Gemini")
        _ = try payload(fileURI: "", hints: hints)
        let started = Date(), deadline = Date().addingTimeInterval(timeout)
        var fileName: String?
        do {
            let wav = WAVEncoder.encode(samples: samples)
            var start = try request("upload/v1beta/files", method: "POST", key: key, deadline: deadline)
            start.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
            start.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
            start.setValue(String(wav.count), forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
            start.setValue("audio/wav", forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
            start.setValue("application/json", forHTTPHeaderField: "Content-Type")
            start.httpBody = try JSONSerialization.data(withJSONObject: ["file": ["display_name": "Airdraft dictation"]])
            let (_, response) = try await http.response(start)
            guard let rawURL = response.value(forHTTPHeaderField: "X-Goog-Upload-URL"), let uploadURL = URL(string: rawURL),
                  uploadURL.scheme == "https", uploadURL.host == Self.host,
                  uploadURL.user == nil, uploadURL.password == nil, uploadURL.port == nil else { throw TranscriberError.invalidResponse }
            var upload = try CloudSpeechResources.request(uploadURL, method: "POST", key: key, header: "x-goog-api-key", prefix: "", deadline: deadline)
            upload.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
            upload.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
            upload.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
            upload.httpBody = wav
            struct File: Decodable { let name: String; let uri: String; let state: String? }
            struct Uploaded: Decodable { let file: File }
            var file = try await http.decode(Uploaded.self, from: upload).file
            guard Self.isFileName(file.name) else { throw TranscriberError.invalidResponse }
            fileName = file.name
            let originalName = file.name
            while file.state == "PROCESSING" {
                try await CloudSpeechResources.pause(interval: pollInterval, deadline: deadline)
                let poll = try request("v1beta/\(originalName)", key: key, deadline: deadline)
                file = try await http.decode(File.self, from: poll)
                guard file.name == originalName else { throw TranscriberError.invalidResponse }
            }
            guard file.state == nil || file.state == "ACTIVE",
                  let uri = URL(string: file.uri), uri.scheme == "https", uri.host == Self.host,
                  uri.path == "/v1beta/\(originalName)", uri.query == nil else { throw TranscriberError.invalidResponse }
            var transcribe = try request("v1beta/interactions", method: "POST", key: key, deadline: deadline)
            transcribe.setValue("2026-05-20", forHTTPHeaderField: "Api-Revision")
            transcribe.setValue("application/json", forHTTPHeaderField: "Content-Type")
            transcribe.httpBody = try JSONSerialization.data(withJSONObject: payload(fileURI: file.uri, hints: hints))
            struct Interaction: Decodable {
                struct Step: Decodable {
                    struct Content: Decodable { let type: String; let text: String? }
                    let type: String; let content: [Content]?
                }
                let status: String
                let steps: [Step]
            }
            let reply = try await http.decode(Interaction.self, from: transcribe)
            guard reply.status == "completed", let output = reply.steps.last(where: { $0.type == "model_output" }),
                  let content = output.content, content.allSatisfy({ $0.type == "text" && $0.text != nil }), !content.isEmpty else {
                throw TranscriberError.invalidResponse
            }
            let text = content.compactMap(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
            await cleanup(fileName, key: key)
            fileName = nil
            try Task.checkCancellation()
            return Transcript(text: text, language: hints.isoLanguage, engine: id, latencyMs: Int(Date().timeIntervalSince(started) * 1000))
        } catch {
            await cleanup(fileName, key: key)
            throw error
        }
    }

    private func request(_ path: String, method: String = "GET", key: String, deadline: Date) throws -> URLRequest {
        try CloudSpeechResources.request(Self.base.appendingPathComponent(path), method: method, key: key,
                                         header: "x-goog-api-key", prefix: "", deadline: deadline)
    }

    private static func isFileName(_ value: String) -> Bool {
        value.hasPrefix("files/") && CloudSpeechResources.isResourceID(String(value.dropFirst(6)))
    }

    private func cleanup(_ name: String?, key: String) async {
        let url = name.flatMap { Self.isFileName($0) ? Self.base.appendingPathComponent("v1beta/\($0)") : nil }
        await CloudSpeechResources.delete(url, key: key, header: "x-goog-api-key", prefix: "", http: http)
    }
}
