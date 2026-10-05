import Foundation

/// The long-file API keeps remote IDs in the document before proceeding to the next request.
public struct SonioxMediaTranscriber: Sendable {
    let key: String
    let session: URLSession
    public init(key: String, session: URLSession = .shared) { self.key = key; self.session = session }
    private func request(_ path: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.soniox.com/v1/")!.appendingPathComponent(path))
        request.httpMethod = method; request.timeoutInterval = 120
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return request
    }
    private func checkedID(_ id: String) throws -> String {
        guard UUID(uuidString: id) != nil else { throw TranscriberError.invalidResponse }
        return id
    }
    public func transcribe(url: URL, stagingDirectory: URL, document: TranscriptDocument,
                           checkpoint: @escaping @Sendable (String?, String?) async throws -> Void) async throws -> [TranscriptWord] {
        let http = TranscriptionHTTP(session: session)
        var fileID = document.remoteFileID
        var jobID = document.remoteJobID
        if fileID == nil {
            try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let multipart = stagingDirectory.appendingPathComponent(UUID().uuidString + ".upload")
            let boundary = UUID().uuidString
            defer { try? FileManager.default.removeItem(at: multipart) }
            FileManager.default.createFile(atPath: multipart.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let out = try FileHandle(forWritingTo: multipart)
            do {
                try out.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"recording.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
                let input = try FileHandle(forReadingFrom: url)
                defer { try? input.close() }
                while let data = try input.read(upToCount: 1_048_576), !data.isEmpty {
                    try Task.checkCancellation(); try out.write(contentsOf: data)
                }
                try out.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8)); try out.close()
            } catch { try? out.close(); throw error }
            var upload = request("files", method: "POST")
            upload.timeoutInterval = 1800
            upload.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            let (data, response) = try await session.upload(for: upload, fromFile: multipart)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw TranscriberError.invalidResponse }
            struct File: Decodable { var id: String }
            fileID = try checkedID(JSONDecoder().decode(File.self, from: data).id)
            try await checkpoint(fileID, nil)
        }
        guard let fileID else { throw TranscriberError.invalidResponse }
        _ = try checkedID(fileID)
        struct Job: Decodable { var id: String; var status: String; var error_message: String? }
        if jobID == nil {
            var create = request("transcriptions", method: "POST")
            create.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var body: [String: Any] = ["model": "stt-async-v5", "file_id": fileID,
                "enable_speaker_diarization": document.configuration.identifySpeakers,
                "enable_language_identification": true]
            if let language = try SpeechLanguagePolicy.resolve(document.configuration.asr).language { body["language_hints"] = [language] }
            create.httpBody = try JSONSerialization.data(withJSONObject: body)
            jobID = try checkedID(await http.decode(Job.self, from: create).id)
            try await checkpoint(fileID, jobID)
        }
        guard let jobID else { throw TranscriberError.invalidResponse }
        _ = try checkedID(jobID)
        let deadline = Date().addingTimeInterval(2 * 60 * 60)
        var attempts = 0
        while true {
            try Task.checkCancellation()
            guard Date() < deadline else { throw TranscriberError.timedOut }
            let job: Job
            do { job = try await http.decode(Job.self, from: request("transcriptions/\(jobID)")); attempts = 0 }
            catch {
                if Task.isCancelled { throw CancellationError() }
                attempts += 1
                guard attempts <= 3 else { throw error }
                try await Task.sleep(for: .seconds(Double(attempts * 2)))
                continue
            }
            guard job.id == jobID else { throw TranscriberError.invalidResponse }
            if job.status == "completed" { break }
            if job.status == "error" { throw TranscriberError.providerFailure("Soniox", job.error_message ?? "Transcription failed.") }
            guard ["queued", "processing"].contains(job.status) else { throw TranscriberError.invalidResponse }
            try await Task.sleep(for: .seconds(2))
        }
        struct Reply: Decodable {
            struct Token: Decodable { var text: String; var start_ms: Double?; var end_ms: Double?; var speaker: String? }
            var tokens: [Token]
        }
        let reply = try await http.decode(Reply.self, from: request("transcriptions/\(jobID)/transcript"))
        return reply.tokens.compactMap { token in
            guard let start = token.start_ms, let end = token.end_ms, start.isFinite, end.isFinite,
                  start >= 0, end >= start, !token.text.hasPrefix("<|") else { return nil }
            return TranscriptWord(start: start / 1000, end: end / 1000, text: token.text, speaker: token.speaker)
        }
    }
    public func cleanup(fileID: String?, jobID: String?) async throws {
        let http = TranscriptionHTTP(session: session)
        var paths: [String] = []
        if let jobID { paths.append("transcriptions/\(try checkedID(jobID))") }
        if let fileID { paths.append("files/\(try checkedID(fileID))") }
        for path in paths {
            do { _ = try await http.send(request(path, method: "DELETE")) }
            catch TranscriberError.http(let status, _) where status == 404 { continue }
        }
    }
}
