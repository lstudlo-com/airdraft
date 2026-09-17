import Foundation
import AirdraftCore

// Headless harness for evaluation and debugging. Same engines as the app;
// local engines load from ~/Library/Application Support/Transcribar/Models.
//
//   airdraft-cli transcribe <audio> [--whisper VARIANT | --qwen3 [ID] | --cohere [ID] | --sensevoice | --firered | --apple [LOCALE] | --elevenlabs [MODEL]]
//                              [--url BASE --model M --key K] [--lang zh] [--vocab "A,B"]
//   airdraft-cli refine "<text>" [--llm-url BASE] [--llm-model M] [--llm-key K] [--mode clean|concise|summary] [--instructions "..."] [--task "..."]
//                           [--family general|email|workChat|personalChat|document|code|terminal] [--dict "Term=alias1,alias2;Term2"]
//   airdraft-cli run <audio> (all of the above flags)
//   airdraft-cli prompt  (print the system prompt for the given --mode/--family/--dict)

struct Args {
    var positional: [String] = []
    var flags: [String: String] = [:]

    init(_ argv: [String]) {
        var i = 0
        while i < argv.count {
            let a = argv[i]
            if a.hasPrefix("--") {
                let key = String(a.dropFirst(2))
                if i + 1 < argv.count, !argv[i + 1].hasPrefix("--") {
                    flags[key] = argv[i + 1]
                    i += 2
                } else {
                    flags[key] = "true"
                    i += 1
                }
            } else {
                positional.append(a)
                i += 1
            }
        }
    }

    subscript(_ key: String) -> String? { flags[key] }

    /// Value of a flag that may be given bare (`--qwen3`) or with a value (`--qwen3 ID`).
    func optionalValue(_ key: String, default value: String) -> String? {
        guard let v = flags[key] else { return nil }
        return v == "true" ? value : v
    }
}

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func parseDictionary(_ spec: String?) -> [DictionaryEntry] {
    guard let spec, !spec.isEmpty else { return [] }
    return spec.split(separator: ";").compactMap { item in
        let parts = item.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let term = parts.first, !term.isEmpty else { return nil }
        let aliases = parts.count > 1 ? parts[1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } : []
        return DictionaryEntry(term: term, aliases: aliases)
    }
}

func makeTranscriber(_ args: Args) -> any Transcriber {
    let defaults = ASRConfig()
    if let id = args.optionalValue("cohere", default: defaults.cohereModel) { return CohereTranscriber(modelId: id) }
    if let id = args.optionalValue("qwen3", default: defaults.qwen3Model) { return Qwen3ASRTranscriber(modelId: id) }
    if args["sensevoice"] != nil { return SherpaTranscriber(model: .senseVoice) }
    if args["firered"] != nil { return SherpaTranscriber(model: .fireRed) }
    if let locale = args.optionalValue("apple", default: defaults.appleLocale) { return AppleSpeechTranscriber(locale: locale) }
    if let model = args.optionalValue("elevenlabs", default: defaults.elevenLabsModel) {
        return ElevenLabsTranscriber(modelId: model, apiKey: args["key"] ?? ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"])
    }
    if let base = args["url"], args["whisper"] == nil {
        guard let url = URL(string: base) else { die("bad --url") }
        return OpenAICompatibleTranscriber(baseURL: url, model: args["model"] ?? defaults.model, apiKey: args["key"])
    }
    return WhisperKitTranscriber(variant: args["whisper"] ?? defaults.whisperModel)
}

func makeRefiner(_ args: Args) -> any Refiner {
    let defaults = LLMConfig()
    guard let url = URL(string: args["llm-url"] ?? defaults.baseURL) else { die("bad --llm-url") }
    return OpenAICompatibleRefiner(
        baseURL: url,
        model: args["llm-model"] ?? defaults.model,
        apiKey: args["llm-key"],
        timeout: Double(args["timeout"] ?? "60") ?? 60
    )
}

func script(_ args: Args) -> ChineseScript {
    ChineseScript(rawValue: args["script"] ?? "traditional") ?? .traditional
}

func refineRequest(_ text: String, _ args: Args) -> RefineRequest {
    let modeName = (args["mode"] ?? "clean").lowercased()
    var profile = RefinementProfile.defaults.first { $0.name.lowercased() == modeName } ?? RefinementProfile.defaults[0]
    if let override = args["instructions"] { profile.instructions = override }
    if let task = args["task"] { profile.task = task }
    let family = AppFamily(rawValue: args["family"] ?? "general") ?? .general
    var ctx = AppContext()
    ctx.selectedText = args["selected"]
    ctx.textBeforeCursor = args["before"]
    ctx.textAfterCursor = args["after"]
    ctx.appName = args["app"]
    ctx.windowTitle = args["window"]
    ctx.url = args["page-url"]
    ctx.recentDictations = args["recent"]?.components(separatedBy: "||") ?? []
    let baseRules = args["base-rules-file"].flatMap { try? String(contentsOfFile: $0, encoding: .utf8) } ?? PromptBuilder.defaultBaseRules
    return RefineRequest(transcript: text, profile: profile, baseRules: baseRules, context: ctx, family: family, dictionary: parseDictionary(args["dict"]), chineseScript: script(args))
}

func refineAndPrint(_ text: String, _ args: Args) async throws {
    let r = try await makeRefiner(args).refine(refineRequest(text, args))
    let final = DictionaryPostProcessor.apply(ChineseScriptConverter.convert(r.text, to: script(args)), entries: parseDictionary(args["dict"]))
    print("[llm] engine=\(r.engine) latency=\(r.latencyMs)ms")
    print(final)
}

let args = Args(Array(CommandLine.arguments.dropFirst()))
guard let command = args.positional.first else {
    die("usage: airdraft-cli transcribe|refine|run|prompt ...")
}

switch command {
case "transcribe", "run":
    guard args.positional.count > 1 else { die("missing audio path") }
    let samples = try AudioFile.load(path: args.positional[1])
    let transcriber = makeTranscriber(args)
    let hints = TranscriptionHints(
        language: args["lang"],
        vocabulary: args["vocab"]?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? [],
        chineseScript: script(args)
    )
    let prepStart = Date()
    try await transcriber.prepare()
    let prepMs = Int(Date().timeIntervalSince(prepStart) * 1000)
    let t = try await transcriber.transcribe(samples: samples, hints: hints)
    print("[asr] engine=\(t.engine) load=\(prepMs)ms decode=\(t.latencyMs)ms audio=\(String(format: "%.1f", Double(samples.count) / 16000))s lang=\(t.language ?? "?")")
    print(t.text)
    if command == "run" { try await refineAndPrint(t.text, args) }

case "refine":
    guard args.positional.count > 1 else { die("missing text") }
    try await refineAndPrint(args.positional[1], args)

case "prompt":
    let req = refineRequest(args.positional.count > 1 ? args.positional[1] : "<transcript>", args)
    print("=== system ===")
    print(PromptBuilder.systemPrompt(for: req))
    print("=== user ===")
    print(PromptBuilder.userMessage(for: req))

default:
    die("unknown command \(command)")
}
