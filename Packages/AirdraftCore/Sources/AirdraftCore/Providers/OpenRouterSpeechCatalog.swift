import Foundation

/// OpenRouter's public speech catalog. The generic /models response also
/// contains chat and other audio models; only transcription output is shown.
public enum OpenRouterSpeechCatalog {
    public static func fetch(session: URLSession = .shared, timeout: TimeInterval = 10) async throws -> [SpeechModelInfo] {
        let data = try await TranscriptionHTTP(session: session).send(modelsRequest(timeout: timeout))
        struct Reply: Decodable {
            struct Model: Decodable {
                struct Architecture: Decodable {
                    let inputModalities: [String]?
                    let outputModalities: [String]?
                    enum CodingKeys: String, CodingKey {
                        case inputModalities = "input_modalities", outputModalities = "output_modalities"
                    }
                }
                let id: String
                let name: String?
                let architecture: Architecture?
            }
            let data: [Model]
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw TranscriberError.invalidResponse
        }
        let curated = Dictionary(uniqueKeysWithValues: SpeechModelInfo.models(for: .openRouter).map { ($0.id, $0) })
        var seen = Set<String>()
        return reply.data.compactMap { model in
            guard model.architecture?.inputModalities?.contains("audio") == true,
                  model.architecture?.outputModalities?.contains("transcription") == true,
                  !model.id.isEmpty, seen.insert(model.id).inserted else { return nil }
            return curated[model.id] ?? placeholder(id: model.id, title: model.name)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    static func modelsRequest(timeout: TimeInterval = 10) -> URLRequest {
        var components = URLComponents(string: "https://openrouter.ai/api/v1/models")!
        components.queryItems = [URLQueryItem(name: "output_modalities", value: "transcription")]
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func placeholder(id: String, title: String? = nil) -> SpeechModelInfo {
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelTitle = title?.isEmpty == false ? title! : id
        var components = URLComponents(string: "https://openrouter.ai")!
        components.path = "/\(id)"
        return SpeechModelInfo(id: id, title: modelTitle, price: "See pricing",
                               billing: "OpenRouter models may bill per audio second or by token. Check this model's current rate.",
                               quality: "Not rated", qualityDetail: "No comparable transcription accuracy is published for this model.",
                               speed: "Not published", speedDetail: "No comparable file-transcription latency is published. Upload and network time affect your wait.",
                               documentationURL: components.url ?? URL(string: "https://openrouter.ai/models")!)
    }
}
