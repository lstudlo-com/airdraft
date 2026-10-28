import Foundation

/// AssemblyAI Universal Streaming v3
/// (https://www.assemblyai.com/docs/api-reference/streaming-api/streaming-api,
/// https://www.assemblyai.com/docs/streaming/common-session-errors-and-closures,
/// https://www.assemblyai.com/docs/getting-started/universal-3-5-pro, checked 2026-10-28).
/// The streaming models are Universal-3.5 Pro Realtime (`universal-3-5-pro`) and
/// Universal-3.6 Pro Realtime (`universal-3-6-pro`). AssemblyAI documents them as
/// real-time variants whose "configuration and settings differ" from async and
/// that are tuned for utterances under about 10 seconds; the streaming API has no
/// `code_switching`/`expected_languages`. So live text is display-only and the
/// batch request still produces the transcript, even where the IDs coincide.
struct AssemblyAIStreaming: StreamingSpeechProvider {
    static let endpoint = URL(string: "wss://streaming.assemblyai.com/v3/ws")!
    /// The batch model Airdraft ships (`universal-3-5-pro`, `universal-3-6-pro-preview`).
    let batchModel: String
    let hints: TranscriptionHints
    let engineID: String
    var matchesBatchModel: Bool { false }

    /// The real-time model of the same generation as the batch model.
    var streamingModel: String {
        batchModel == "universal-3-6-pro-preview" ? "universal-3-6-pro" : "universal-3-5-pro"
    }

    var queryItems: [URLQueryItem] {
        var items = [URLQueryItem(name: "speech_model", value: streamingModel),
                     URLQueryItem(name: "encoding", value: "pcm_s16le"),
                     URLQueryItem(name: "sample_rate", value: String(sampleRate)),
                     URLQueryItem(name: "language_detection", value: "true")]
        // The batch request's expected languages: the selected language plus English.
        let config = ASRConfig(kind: .assemblyAI, model: batchModel, language: hints.languageCode ?? "auto")
        if let language = (try? SpeechLanguagePolicy.resolve(config))?.language,
           let codes = Self.jsonArray(Array(Set([language, "en"])).sorted()) {
            items.append(URLQueryItem(name: "language_codes", value: codes))
        }
        // Same terms as the batch keyterms_prompt; streaming also caps each at 50 characters.
        let terms = hints.vocabularyTerms
            .filter { $0.split(whereSeparator: \.isWhitespace).count <= 6 && $0.count <= 50 }
            .prefix(100)
        if !terms.isEmpty, let value = Self.jsonArray(Array(terms)) {
            items.append(URLQueryItem(name: "keyterms_prompt", value: value))
        }
        return items
    }

    func request(apiKey: String) async throws -> URLRequest {
        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        // URLComponents leaves "+" literal, which servers read as a space ("C++").
        let encoded = components?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        components?.percentEncodedQuery = encoded
        guard let url = components?.url else { throw StreamingError.invalidMessage }
        var request = URLRequest(url: url)
        // The key itself, without "Bearer".
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        return request
    }

    func startFrames() -> [StreamingFrame] { [] }

    func audioFrame(_ pcm16: Data) -> StreamingFrame { .data(pcm16) }

    /// ForceEndpoint finalizes the open turn; Terminate flushes and ends the
    /// session with a Termination message.
    func endFrames() -> [StreamingFrame] { [.json(["type": "ForceEndpoint"]), .json(["type": "Terminate"])] }

    func makeParser() -> any StreamingParser { Parser() }

    private static func jsonArray(_ values: [String]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: values) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Turn messages carry the whole turn so far; an end-of-turn Turn is its final,
    /// formatted text. Turns are keyed by `turn_order`, so a repeated final replaces
    /// the earlier one, and joined in order.
    final class Parser: StreamingParser {
        private var turns: [Int: String] = [:]
        private var provisionalTurn: Int?
        private(set) var finalText = ""
        private(set) var provisional = ""
        private(set) var language: String?
        private(set) var finished = false

        func consume(_ frame: StreamingFrame) throws {
            guard let object = frame.jsonObject else { throw StreamingError.invalidMessage }
            let type = object["type"] as? String
            if type == "Error" || object["error"] != nil {
                let message = object["error"] as? String ?? (object["error_code"].map { "\($0)" } ?? "Unknown error")
                throw StreamingError.provider("AssemblyAI: \(message)")
            }
            switch type {
            case "Turn":
                let text = (object["transcript"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let turn = object["turn_order"] as? Int ?? (turns.keys.max() ?? -1) + 1
                if language == nil, let code = object["language_code"] as? String, !code.isEmpty { language = code }
                if object["end_of_turn"] as? Bool == true {
                    turns[turn] = text
                    finalText = turns.sorted { $0.key < $1.key }
                        .reduce("") { ModelSpeechPreview.join($0, $1.value) }
                    if provisionalTurn == nil || provisionalTurn == turn {
                        provisional = ""
                        provisionalTurn = nil
                    }
                } else if turns[turn] == nil {
                    provisional = text
                    provisionalTurn = turn
                }
            case "Termination":
                provisional = ""
                provisionalTurn = nil
                finished = true
            default:
                // Begin, SpeechStarted, Heartbeat, SpeakerRevision.
                break
            }
        }
    }
}
