import Foundation

public struct SpeechConnectionResult: Sendable, Equatable {
    public let modelAvailable: Bool
    public var catalogIsPublic = false
    public var message: String {
        if catalogIsPublic { return "Key accepted. Selected speech model is listed in OpenRouter's public catalog. Speech access and billing are not verified." }
        return modelAvailable ? "Connected. The selected model is listed for this key." : "Connected. API key accepted."
    }
}

public enum SpeechConnectionError: LocalizedError, Equatable {
    case missingKey, unsupportedProvider, invalidResponse, invalidKey, permissionDenied, rateLimited, timedOut, network, modelUnavailable, openRouterModelUnlisted
    case server(Int)

    public var errorDescription: String? {
        switch self {
        case .missingKey: return "Enter an API key before testing."
        case .unsupportedProvider: return "Connection testing is unavailable for this provider."
        case .invalidResponse: return "The service returned an unexpected response. Try again later."
        case .invalidKey: return "The API key was rejected. Check the key and its permissions in the provider console."
        case .permissionDenied: return "This key cannot run the connection check. Check account or model-read permissions in the provider console; speech access is separate."
        case .rateLimited: return "The provider's rate or quota limit was reached. Check your account and try again later."
        case .timedOut: return "The connection timed out. Check your network and try again."
        case .network: return "Could not reach the provider. Check your internet connection and try again."
        case .modelUnavailable: return "The key connected, but the selected model was not listed. Check model access or choose another model."
        case .openRouterModelUnlisted: return "The OpenRouter key is valid, but this model is not in the current public speech catalog. Refresh the catalog or choose another model."
        case .server(let status): return "The provider returned HTTP \(status). Try again later."
        }
    }
}

/// Authenticated read-only checks. Never records, uploads audio, or generates a transcript.
/// A successful check does not establish transcription permissions, billing or quality.
public struct SpeechConnectionChecker: Sendable {
    private let http: TranscriptionHTTP
    private let timeout: TimeInterval

    public init(session: URLSession = .shared, timeout: TimeInterval = 10) {
        http = TranscriptionHTTP(session: session)
        self.timeout = timeout
    }

    public func check(config: ASRConfig, apiKey: String) async throws -> SpeechConnectionResult {
        try Task.checkCancellation()
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw SpeechConnectionError.missingKey }
        guard let preset = config.kind.preset else { throw SpeechConnectionError.unsupportedProvider }
        let path: String
        switch config.kind {
        case .openRouter: path = "key"
        case .elevenLabs: path = "user"
        case .deepgram: path = "auth/token"
        default: path = "models"
        }
        var request = URLRequest(url: URL(string: preset.baseURL)!.appendingPathComponent(path), cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        switch config.kind {
        case .elevenLabs: request.setValue(key, forHTTPHeaderField: "xi-api-key")
        case .deepgram: request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        default: request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        let data = try await send(request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              !json.isEmpty, json["error"] == nil, json["err_code"] == nil else { throw SpeechConnectionError.invalidResponse }
        switch config.kind {
        case .openRouter:
            // /models is public, including when an invalid Bearer token is sent.
            // Authenticate against /key first, then check the filtered catalog.
            guard json["data"] is [String: Any] else { throw SpeechConnectionError.invalidResponse }
            let modelData = try await send(OpenRouterSpeechCatalog.modelsRequest(timeout: timeout))
            guard let catalog = try? JSONSerialization.jsonObject(with: modelData) as? [String: Any],
                  let models = catalog["data"] as? [[String: Any]],
                  models.allSatisfy({ $0["id"] is String }) else { throw SpeechConnectionError.invalidResponse }
            guard models.contains(where: { model in
                (model["id"] as? String) == config.model &&
                ((model["architecture"] as? [String: Any])?["input_modalities"] as? [String])?.contains("audio") == true &&
                ((model["architecture"] as? [String: Any])?["output_modalities"] as? [String])?.contains("transcription") == true
            }) else { throw SpeechConnectionError.openRouterModelUnlisted }
            return SpeechConnectionResult(modelAvailable: true, catalogIsPublic: true)
        case .openAI, .groq, .soniox:
            let field = config.kind == .soniox ? "models" : "data"
            guard let models = json[field] as? [[String: Any]], models.allSatisfy({ $0["id"] is String }) else {
                throw SpeechConnectionError.invalidResponse
            }
            guard models.contains(where: { ($0["id"] as? String) == config.selectedSpeechModel?.id }) else {
                throw SpeechConnectionError.modelUnavailable
            }
            return SpeechConnectionResult(modelAvailable: true)
        case .elevenLabs:
            guard let user = json["user_id"] as? String, !user.isEmpty else { throw SpeechConnectionError.invalidResponse }
        case .deepgram:
            // /auth/token documents a JSON object of key details, without a stable public schema.
            break
        default: throw SpeechConnectionError.unsupportedProvider
        }
        return SpeechConnectionResult(modelAvailable: false)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        do {
            let data = try await http.send(request)
            try Task.checkCancellation()
            return data
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            // Only fixed messages leave this boundary; response bodies can contain secrets.
            if case TranscriberError.http(let status, let body) = error {
                if status == 403 || ((status == 401) && body.contains("missing_permissions")) { throw SpeechConnectionError.permissionDenied }
                if status == 401 { throw SpeechConnectionError.invalidKey }
                if status == 429 { throw SpeechConnectionError.rateLimited }
                throw SpeechConnectionError.server(status)
            }
            if case TranscriberError.timedOut = error { throw SpeechConnectionError.timedOut }
            if (error as? URLError)?.code == .timedOut { throw SpeechConnectionError.timedOut }
            throw SpeechConnectionError.network
        }
    }
}
