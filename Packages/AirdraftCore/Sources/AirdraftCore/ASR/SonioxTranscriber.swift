import Foundation
import os

/// File upload -> async job -> poll -> text. Cleanup is scoped to this call's IDs.
public struct SonioxTranscriber: Transcriber {
    public let id = "soniox:stt-async-v5"
    public let apiKey: String?
    public let timeout: TimeInterval
    private let http: TranscriptionHTTP
    private let pollInterval: TimeInterval
    private static let log = Logger(subsystem: AppIdentity.logSubsystem, category: "soniox")

    public init(apiKey: String?, timeout: TimeInterval = 60, session: URLSession = .shared, pollInterval: TimeInterval = 0.5) {
        self.apiKey = apiKey
        self.timeout = timeout
        self.http = TranscriptionHTTP(session: session)
        self.pollInterval = max(0.01, pollInterval)
    }

    public func prepare() async throws {}

    func payload(fileID: String, hints: TranscriptionHints) -> [String: Any] {
        var body: [String: Any] = ["model": "stt-async-v5", "file_id": fileID, "enable_language_identification": true]
        if let language = hints.isoLanguage { body["language_hints"] = [language] }
        // Hints stay non-strict so Chinese/English code-switching remains possible.
        let terms = hints.vocabularyTerms.prefix(100).map { String($0.prefix(100)) }
        if !terms.isEmpty { body["context"] = ["terms": terms] }
        return body
    }

    private func request(_ path: String, method: String = "GET", key: String, deadline: Date) throws -> URLRequest {
        try Task.checkCancellation()
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { throw TranscriberError.timedOut }
        var request = URLRequest(url: URL(string: "https://api.soniox.com/v1")!.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = remaining
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return request
    }

    public func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        guard !samples.isEmpty else { throw TranscriberError.emptyAudio }
        let key = try TranscriptionHTTP.requireKey(apiKey, provider: "Soniox")
        let started = Date()
        let deadline = started.addingTimeInterval(timeout)
        var fileID: String?
        var jobID: String?
        do {
            struct Upload: Decodable { let id: String }
            let form = MultipartForm()
            var upload = try request("files", method: "POST", key: key, deadline: deadline)
            upload.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
            upload.httpBody = form.body(fields: [], wav: WAVEncoder.encode(samples: samples))
            fileID = try await http.decode(Upload.self, from: upload).id
            guard let fileID, UUID(uuidString: fileID) != nil else { throw TranscriberError.invalidResponse }

            struct Job: Decodable { let id: String; let status: String; let error_message: String? }
            var create = try request("transcriptions", method: "POST", key: key, deadline: deadline)
            create.setValue("application/json", forHTTPHeaderField: "Content-Type")
            create.httpBody = try JSONSerialization.data(withJSONObject: payload(fileID: fileID, hints: hints))
            var job = try await http.decode(Job.self, from: create)
            guard UUID(uuidString: job.id) != nil else { throw TranscriberError.invalidResponse }
            jobID = job.id
            while job.status != "completed" {
                if job.status == "error" { throw TranscriberError.providerFailure("Soniox", job.error_message ?? "Transcription failed.") }
                guard ["queued", "processing"].contains(job.status) else { throw TranscriberError.invalidResponse }
                guard deadline.timeIntervalSinceNow > 0 else { throw TranscriberError.timedOut }
                try await Task.sleep(for: .seconds(max(0, min(pollInterval, deadline.timeIntervalSinceNow))))
                let poll = try request("transcriptions/\(job.id)", key: key, deadline: deadline)
                let next = try await http.decode(Job.self, from: poll)
                guard next.id == job.id else { throw TranscriberError.invalidResponse }
                job = next
            }
            struct Reply: Decodable {
                struct Token: Decodable { let language: String? }
                let text: String
                let tokens: [Token]?
            }
            let result = try request("transcriptions/\(job.id)/transcript", key: key, deadline: deadline)
            let reply = try await http.decode(Reply.self, from: result)
            var transcript = Transcript(text: reply.text.trimmingCharacters(in: .whitespacesAndNewlines),
                                        language: reply.tokens?.compactMap(\.language).first ?? hints.isoLanguage,
                                        engine: id, latencyMs: Int(Date().timeIntervalSince(started) * 1000))
            await cleanup(fileID: fileID, jobID: jobID, key: key)
            transcript.latencyMs = Int(Date().timeIntervalSince(started) * 1000)
            return transcript
        } catch {
            await cleanup(fileID: fileID, jobID: jobID, key: key)
            throw error
        }
    }

    private func cleanup(fileID: String?, jobID: String?, key: String) async {
        // A cancelled dictation must still attempt cleanup. Never delete anything
        // except the resources returned by this invocation, and never log audio/keys.
        await Task.detached {
            var paths: [String] = []
            if let jobID, UUID(uuidString: jobID) != nil { paths.append("transcriptions/\(jobID)") }
            if let fileID, UUID(uuidString: fileID) != nil { paths.append("files/\(fileID)") }
            for path in paths {
                do {
                    let deletion = try request(path, method: "DELETE", key: key, deadline: Date().addingTimeInterval(2))
                    _ = try await http.send(deletion)
                } catch {
                    Self.log.warning("Could not delete a Soniox resource. Check the Soniox console for retained uploads.")
                }
            }
        }.value
    }
}
