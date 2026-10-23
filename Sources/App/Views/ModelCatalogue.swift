import AirdraftCore
import SwiftUI

/// One downloadable or built-in speech model.
/// Everything else (installed, loaded, download, delete) derives from `select`.
struct ModelEntry: Identifiable, Sendable {
    enum Storage: Sendable { case download(sizeLabel: String), builtIn }
    let id: String
    let title: String
    let vendor: String
    let provider: String
    let brand: ModelBrand
    /// Runtime tags such as Core ML or a GGUF quantization. Languages come from
    /// `SpeechLanguagePolicy` through `languages`.
    let tags: [String]
    let speed: Int      // 1...5 relative rating; 0 means unrated
    let accuracy: Int   // 1...5 relative rating; 0 means unrated
    let storage: Storage
    let note: String
    /// Points a speech config at this model.
    let select: @Sendable (inout ASRConfig) -> Void

    /// The title comes from Core's `ASRConfig.modelDisplayName`, the name Home,
    /// Profiles and the menu show, so the Models table cannot drift from it.
    init(id: String, vendor: String, provider: String, brand: ModelBrand, tags: [String], speed: Int, accuracy: Int,
         storage: Storage, note: String, select: @escaping @Sendable (inout ASRConfig) -> Void) {
        var config = ASRConfig()
        select(&config)
        self.id = id
        self.title = config.modelDisplayName
        self.vendor = vendor
        self.provider = provider
        self.brand = brand
        self.tags = tags
        self.speed = speed
        self.accuracy = accuracy
        self.storage = storage
        self.note = note
        self.select = select
    }

    func config(from base: ASRConfig) -> ASRConfig {
        var config = base
        select(&config)
        return config
    }

    func isSelected(_ current: ASRConfig) -> Bool {
        let mine = config(from: current)
        guard mine.kind == current.kind else { return false }
        return mine.engineID == current.engineID
    }

    var isDownloadable: Bool { if case .download = storage { return true } else { return false } }

    /// AD-071: whether Airdraft has evidence that this entry downloads, loads and
    /// transcribes. Built-in Apple Speech is provided by macOS and has no tier.
    var tier: ModelTier? {
        guard isDownloadable else { return nil }
        return ModelCatalogue.verificationEvidence[id] == nil ? .experimental : .verified
    }

    /// The visible strength of an entry outside the recommended set.
    var highlight: String? {
        id == LocalSpeechRecommendation.Model.qwen3Large.catalogueID
            ? String(localized: "Best for mixed Chinese and English") : nil
    }

    /// Supported languages with full names, the user's language first; nil when
    /// macOS owns them (Apple Speech). Cached, since names are formatted per code.
    @MainActor var languages: SpeechLanguageList? {
        if let cached = ModelCatalogue.languageCache[id] { return cached }
        let list = SpeechLanguageList.supported(by: config(from: ASRConfig()), preferredLanguage: ModelCatalogue.systemLanguage)
        ModelCatalogue.languageCache[id] = .some(list)
        return list
    }

    /// The compact language form shown in the row, such as
    /// "Mandarin Chinese, English and 28 more".
    @MainActor var languageSummary: String {
        guard let list = languages else { return String(localized: "Languages set in macOS") }
        guard list.remaining > 0 else { return list.shown.formatted(.list(type: .and)) }
        return String(localized: "\(list.shown[0]), \(list.shown[1]) and \(list.remaining) more")
    }

    /// Every supported language, for the tooltip.
    @MainActor var languageDetail: String {
        guard let list = languages else { return String(localized: "Uses the Apple Speech locale chosen in Speech options.") }
        if list.names.count == 1 { return String(localized: "Supports \(list.names[0]) only.") }
        return String(localized: "Supports \(list.names.count) languages: \(list.names.formatted(.list(type: .and)))")
    }
}

extension LocalModelShortlist.Role {
    /// The one visible label a recommended-set row shows.
    func label(for reason: LocalSpeechRecommendation.Reason) -> (symbol: String, text: String) {
        switch self {
        case .recommended:
            switch reason {
            case .mixedChineseEnglish: ("star.fill", String(localized: "Best for mixed Chinese and English"))
            case .limitedMemory: ("star.fill", String(localized: "Best fit for this Mac's memory"))
            case .systemLanguage: ("star.fill", String(localized: "Best fit for your language"))
            }
        case .faster: ("hare", String(localized: "Smaller and faster"))
        case .smaller: ("arrow.down.forward.and.arrow.up.backward", String(localized: "Smaller download"))
        case .fullSize: ("scope", String(localized: "Full-size model, larger download"))
        case .singleLanguage: ("text.bubble", String(localized: "Built for one language"))
        case .mixedChineseEnglish: ("character.bubble", String(localized: "Best for mixed Chinese and English"))
        case .mandarin: ("scope", String(localized: "Best Mandarin accuracy, 20+ dialects"))
        case .multilingual: ("globe", String(localized: "More languages, larger download"))
        }
    }
}

enum ModelTier: Equatable {
    case verified, experimental

    var title: String {
        switch self {
        case .verified: String(localized: "Verified")
        case .experimental: String(localized: "Experimental")
        }
    }

    var symbol: String {
        switch self {
        case .verified: "checkmark.seal"
        case .experimental: "flask"
        }
    }

    var detail: String {
        switch self {
        case .verified: String(localized: "Downloaded, loaded and used to transcribe in Airdraft's own tests.")
        case .experimental: String(localized: "Not yet tested end to end in Airdraft. It may fail to load or transcribe poorly.")
        }
    }
}

enum ModelCatalogue {
    /// Pinned bytes, so the label matches what the download actually fetches.
    private static func qwenSize(_ model: String) -> String { PinnedHubModelCatalog.qwen3(model)?.sizeLabel ?? "" }

    static let entries: [ModelEntry] = [
        ModelEntry(
            id: "qwen3:1.7b", vendor: "Alibaba · MLX", provider: "Alibaba", brand: .qwen,
            tags: [], speed: 4, accuracy: 5, storage: .download(sizeLabel: qwenSize("aufklarer/Qwen3-ASR-1.7B-MLX-5bit")),
            note: String(localized: "Best for mixed Chinese and English.")
        ) { $0.kind = .qwen3; $0.qwen3Model = "aufklarer/Qwen3-ASR-1.7B-MLX-5bit" },
        ModelEntry(
            id: "qwen3:0.6b", vendor: "Alibaba · MLX", provider: "Alibaba", brand: .qwen,
            tags: [], speed: 5, accuracy: 3, storage: .download(sizeLabel: qwenSize("aufklarer/Qwen3-ASR-0.6B-MLX-4bit")),
            note: String(localized: "Low memory, very fast.")
        ) { $0.kind = .qwen3; $0.qwen3Model = "aufklarer/Qwen3-ASR-0.6B-MLX-4bit" },
        ModelEntry(
            id: "sherpa:fireRed", vendor: "FireRed · ONNX", provider: "FireRed", brand: .fireRed,
            tags: [], speed: 3, accuracy: 5, storage: .download(sizeLabel: SherpaTranscriber.Model.fireRed.sizeLabel),
            note: String(localized: "Best Mandarin accuracy, 20+ dialects.")
        ) { $0.kind = .fireRed },
        ModelEntry(
            id: "cohere", vendor: "Cohere · MLX", provider: "Cohere", brand: .cohere,
            tags: [], speed: 4, accuracy: 5, storage: .download(sizeLabel: "1.6 GB"),
            note: String(localized: "Best open English model.")
        ) { $0.kind = .cohere; $0.cohereModel = "aufklarer/Cohere-Transcribe-2B-MLX-5bit" },
        ModelEntry(
            id: "sherpa:senseVoice", vendor: "FunAudioLLM · ONNX", provider: "Alibaba", brand: .alibaba,
            tags: [], speed: 5, accuracy: 3, storage: .download(sizeLabel: SherpaTranscriber.Model.senseVoice.sizeLabel),
            note: String(localized: "Smaller and faster; weaker with English terms in Chinese speech.")
        ) { $0.kind = .senseVoice },
        ModelEntry(
            id: "sherpa:parakeet", vendor: "NVIDIA · ONNX", provider: "NVIDIA", brand: .nvidia,
            tags: [], speed: 0, accuracy: 0, storage: .download(sizeLabel: SherpaTranscriber.Model.parakeet.sizeLabel),
            note: String(localized: "25 European languages. Does not support Chinese.")
        ) { $0.kind = .parakeet },
        ModelEntry(
            id: "apple", vendor: "macOS 26 · Neural Engine", provider: "Apple", brand: .apple,
            tags: [], speed: 5, accuracy: 3, storage: .builtIn,
            note: String(localized: "macOS manages language assets.")
        ) { $0.kind = .apple },
    ] + WhisperModelVariant.allCases.map { variant in
        ModelEntry(id: variant == .turbo ? "whisper:turbo" : "whisper:\(variant.rawValue)", vendor: variant.isEnglishOnly ? "Hugging Face · Core ML" : "OpenAI · Core ML",
                   provider: variant.isEnglishOnly ? "Hugging Face" : "OpenAI", brand: variant.isEnglishOnly ? .huggingFace : .openAI,
                   tags: ["Core ML"], speed: variant == .turbo ? 3 : 0,
                   accuracy: variant == .turbo ? 3 : 0, storage: .download(sizeLabel: variant.sizeLabel),
                   note: variant.note) { $0.kind = .whisperKit; $0.whisperModel = variant.rawValue }
    } + [
        ModelEntry(id: "sherpa:orukeet", vendor: "Oruk · ONNX", provider: "Oruk", brand: .oruk,
                   tags: ["ONNX"], speed: 0, accuracy: 0, storage: .download(sizeLabel: "487 MB"),
                   note: String(localized: "25 European languages; no Chinese support.")) { $0.kind = .orukeet }
    ] + CoreMLSpeechModelCatalog.models.map { model in
        ModelEntry(id: "coreml:\(model.id)", vendor: "\(model.creator) · Core ML", provider: model.creator,
                   brand: model.creator == "Moondream" ? .moondream : model.creator == "Fermion Research" ? .fermion : .nvidia,
                   tags: ["Core ML"],
                   speed: 0, accuracy: 0, storage: .download(sizeLabel: model.sizeLabel), note: model.languageCapabilities.summary) {
            $0.kind = .fluidAudio; $0.model = model.id
        }
    } + GGUFModelCatalog.models.map { model in
        ModelEntry(id: "gguf:\(model.id)", vendor: "\(model.creator) · GGUF \(model.quantization)", provider: model.creator,
                          brand: ModelBrand(rawValue: model.brand)!, tags: ["GGUF \(model.quantization)"],
                          speed: 0, accuracy: 0, storage: .download(sizeLabel: model.sizeLabel),
                          note: model.languageCapabilities.summary) { $0.kind = .transcribeCpp; $0.model = model.id }
    }
}

extension ModelCatalogue {
    /// Local entries with recorded download, load and transcription evidence
    /// (AD-071). Keep the source beside each ID; every other download is
    /// Experimental until it gains the same evidence.
    static let verificationEvidence: [String: String] = {
        let coverage = "Vault Records/Verification/2026-10-12 Local Speech Model Coverage"
        let mixed = "eval/mixed-asr (2026-10-21, source 2242fb4)"
        var evidence = Dictionary(uniqueKeysWithValues: [
            "coreml:parakeet-v2", "coreml:parakeet-v3", "coreml:parakeet-v3-int4", "coreml:parakeet-ultra",
            "coreml:parakeet-redux", "coreml:phonon-2", "coreml:parakeet-110m", "coreml:parakeet-ja",
            "gguf:whisper-tiny", "gguf:moonshine-tiny", "gguf:moonshine-tiny-zh", "gguf:breeze-asr-25",
            "gguf:canary-180m-flash", "gguf:fun-asr-nano-2512", "gguf:gigaam-v3-ctc",
            "sherpa:orukeet", "whisper:large-v3", "whisper:distil-large-v3_594MB",
        ].map { ($0, coverage) })
        for id in ["qwen3:1.7b", "qwen3:0.6b", "sherpa:senseVoice", "sherpa:fireRed", "whisper:turbo"] {
            evidence[id] = mixed
        }
        return evidence
    }()

    /// The shortlist first, then the rest of the verified and built-in entries,
    /// then Experimental ones, each in catalogue order.
    static func grouped(_ entries: [ModelEntry], shortlist: LocalModelShortlist)
        -> (recommended: [(ModelEntry, LocalModelShortlist.Role)], verified: [ModelEntry], experimental: [ModelEntry]) {
        let recommended = shortlist.picks.compactMap { pick in entries.first { $0.id == pick.id }.map { ($0, pick.role) } }
        let order = Set(shortlist.ids)
        let rest = entries.filter { !order.contains($0.id) }
        return (recommended, rest.filter { $0.tier != .experimental }, rest.filter { $0.tier == .experimental })
    }

    /// AD-071. By default (`showsAll` off, not searching) Models lists only the
    /// compact recommended set, then "Your models": the entries in `inUse` (app
    /// default, profile binding, installed or downloading) that the set does not
    /// show. Showing all models, or searching, lists Recommended, then Verified
    /// (with built-in) rows, then the Experimental disclosure. Collapsed, that
    /// group still lists the Experimental entries in `inUse`, so a model the user
    /// relies on never disappears. Expanded or searching, it lists every
    /// Experimental entry in catalogue order.
    static func localItems(_ entries: [ModelEntry], shortlist: LocalModelShortlist, inUse: Set<String>,
                           showsAll: Bool, expanded: Bool, searching: Bool) -> [LocalModelItem] {
        let groups = grouped(entries, shortlist: shortlist)
        var items: [LocalModelItem] = []
        let recommendedHeader: LocalModelItem.Header = shortlist.recommendation.reason == .limitedMemory ? .recommendedForMemory : .recommended
        for (index, (entry, role)) in groups.recommended.enumerated() {
            items.append(.model(entry, header: index == 0 ? recommendedHeader : nil, role: role))
        }
        guard showsAll || searching else {
            let yours = shortlist.inUse(catalogueOrder: entries.map(\.id), inUse: inUse)
            for (index, id) in yours.enumerated() {
                guard let entry = entries.first(where: { $0.id == id }) else { continue }
                items.append(.model(entry, header: index == 0 ? .yourModels : nil, role: nil))
            }
            return items
        }
        for (index, entry) in groups.verified.enumerated() {
            let labelled = !groups.recommended.isEmpty || !groups.experimental.isEmpty
            items.append(.model(entry, header: index == 0 && labelled ? .verified : nil, role: nil))
        }
        if !groups.experimental.isEmpty {
            let kept = groups.experimental.filter { inUse.contains($0.id) }
            let open = expanded || searching
            items.append(.experimental(count: groups.experimental.count, kept: open ? 0 : kept.count,
                                       expanded: open, searching: searching))
            items += (open ? groups.experimental : kept).map { .model($0, header: nil, role: nil) }
        }
        return items
    }

    /// One recommendation for first-run setup and Models (AD-074). Renders inject
    /// the system language and memory so both cases can be inspected on any Mac.
    static var recommendation: LocalSpeechRecommendation { shortlist.recommendation }

    /// The compact set Models opens with (AD-071), for the same language and memory.
    static var shortlist: LocalModelShortlist {
        .make(languageCode: systemLanguage, physicalMemory: physicalMemory)
    }

    static var systemLanguage: String? {
        RenderMode.value("SYSTEM_LANGUAGE") ?? LocalSpeechRecommendation.systemLanguageCode
    }

    static var physicalMemory: UInt64 {
        RenderMode.value("MEMORY_GB").flatMap { UInt64($0) }.map { $0 << 30 } ?? ProcessInfo.processInfo.physicalMemory
    }

    @MainActor static var languageCache: [String: SpeechLanguageList?] = [:]

    static func entry(_ model: LocalSpeechRecommendation.Model) -> ModelEntry {
        entries.first { $0.id == model.catalogueID }!
    }
}

/// Shared column geometry keeps both tables aligned, including at the minimum window width.
struct ModelComparisonColumns<Identity: View, Speed: View, Accuracy: View, Cost: View, Accessory: View>: View {
    @ViewBuilder var identity: Identity
    @ViewBuilder var speed: Speed
    @ViewBuilder var accuracy: Accuracy
    @ViewBuilder var cost: Cost
    @ViewBuilder var accessory: Accessory
    /// Rating columns widen at half the text-size step: enough for their headings
    /// ("Accuracy" at Larger) while leaving the model names most of the row.
    @Environment(\.textScale) private var textScale
    private var scale: CGFloat { 1 + (textScale - 1) / 2 }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.controlSpacing) {
            identity.frame(maxWidth: .infinity, alignment: .leading)
            speed.frame(width: 56 * scale, alignment: .leading)
            accuracy.frame(width: 64 * scale, alignment: .leading)
            cost.frame(width: 76 * scale, alignment: .leading)
            accessory.frame(width: 20)
        }
    }
}

/// Keep headings visible while the measured row content scrolls within one cap.
/// Short and empty results use only the space they need. The compact
/// recommended set (`capped` false) shows its few rows without an inner scroll.
struct ModelTable<Rows: View>: View {
    let cost: String
    let rowCount: Int
    var capped = true
    @ViewBuilder var rows: Rows
    @State private var contentHeight = Theme.modelTableMaxHeight
    private var maxHeight: CGFloat { capped ? Theme.modelTableMaxHeight : .infinity }

    var body: some View {
        Card(padding: 0) {
            ModelTableHeader(cost: cost)
            RowDivider()
            Group {
                if rowCount > 6 {
                    // Native List virtualizes rows and owns accessibility
                    // scrolling without traversing a lazy SwiftUI identity tree.
                    List {
                        rows
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .contentMargins(0, for: .scrollContent)
                    .environment(\.defaultMinListRowHeight, 60)
                } else {
                    ScrollView(.vertical) {
                        VStack(spacing: 0) { rows }
                            .onGeometryChange(for: CGFloat.self) { [maxHeight] in
                                min($0.size.height, maxHeight)
                            } action: { contentHeight = $0 }
                    }
                }
            }
            .frame(height: rowCount > 6 ? Theme.modelTableMaxHeight : min(contentHeight, maxHeight))
            .scrollBounceBehavior(.basedOnSize)
            #if DEBUG
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                ModelsPerformanceVerification.noteViewport($0)
            }
            #endif
        }
    }
}

struct ModelTableHeader: View {
    let cost: String
    var body: some View {
        ModelComparisonColumns {
            Text("Model")
        } speed: {
            Text("Speed")
        } accuracy: {
            Text("Accuracy")
        } cost: {
            Text(cost)
        } accessory: {
            Color.clear.frame(height: 1)
        }
        .appFont(.detail, weight: .medium)
        .foregroundStyle(.secondary)
        .padding(Theme.cardPadding)
    }
}

struct ModelMetric: View {
    let title: String
    let fraction: Double?
    let label: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SegmentMeter(fraction: fraction)
            Text(label).appFont(.supporting).monospacedDigit().foregroundStyle(.secondary)
        }
        .help(detail)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(label). \(detail)")
        .accessibilityAddTraits(.isStaticText)
    }
}

struct CloudModelRow: View {
    @Environment(AppContainer.self) private var container
    let preset: EndpointPreset.Speech
    let model: SpeechModelInfo
    @State private var hovering = false

    var body: some View {
        let selected = container.settings.asr.kind == preset.kind && container.settings.asr.model == model.id
        Button {
            container.settings.asr.select(preset.kind)
            container.settings.asr.selectModel(model.id)
        } label: {
            ModelComparisonColumns {
                HStack(spacing: 8) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                    ModelBrandIcon(brand: .speech(model, hostedBy: preset.kind))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.title).appFont(.body, weight: .medium)
                        Text(preset.name).supportingText()
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            } speed: {
                ModelMetric(title: String(localized: "Speed"), fraction: speedFraction,
                            label: model.realtimeSpeedFactor.map { "\($0.formatted())×" } ?? String(localized: "Not rated"),
                            detail: model.speedDetail)
            } accuracy: {
                ModelMetric(title: String(localized: "Accuracy"), fraction: model.wordErrorRate.map { 1 - $0 / 100 },
                            label: model.wordErrorRate.map { String(localized: "\($0.formatted())% WER") } ?? String(localized: "Not rated"),
                            detail: model.qualityDetail + " " + (model.wordErrorRate == nil ? String(localized: "No numeric rating is available.")
                                : String(localized: "WER is word error rate; lower is better.")))
            } cost: {
                Text(model.price).appFont(.detail).monospacedDigit().foregroundStyle(.secondary)
                    .help(model.billing)
            } accessory: {
                Color.clear.frame(height: 1)
            }
            .padding(Theme.cardPadding)
            .background(selected ? Color.primary.opacity(0.06) : (hovering ? Color.primary.opacity(0.03) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(model.title), hosted by \(preset.name), \(model.quality), speed: \(model.speed), \(model.price)")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .help(model.qualityDetail + " " + model.speedDetail)
    }

    private var speedFraction: Double? {
        guard let factor = model.realtimeSpeedFactor,
              let fastest = SpeechModelInfo.models(for: preset.kind).compactMap(\.realtimeSpeedFactor).max(),
              fastest > 0 else { return nil }
        return factor / fastest
    }
}

/// One cell of the local models table (AD-071).
enum LocalModelItem: Identifiable {
    enum Header { case recommended, recommendedForMemory, yourModels, verified }
    /// `role` is set for the compact recommended set and names its one label.
    case model(ModelEntry, header: Header?, role: LocalModelShortlist.Role?)
    /// `kept` counts Experimental rows listed while collapsed because they are in use.
    case experimental(count: Int, kept: Int, expanded: Bool, searching: Bool)

    var id: String {
        switch self {
        case .model(let entry, _, _): entry.id
        case .experimental: "experimental-disclosure"
        }
    }
}

struct LocalModelGroupHeader: View {
    let header: LocalModelItem.Header

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).appFont(.detail, weight: .semibold).foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            if header == .recommendedForMemory {
                Text("The smaller model comes first because this Mac has 8 GB of memory or less.").supportingText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.cardPadding)
        .padding(.top, 12)
    }

    private var title: String {
        switch header {
        case .recommended, .recommendedForMemory: String(localized: "Recommended for your language")
        case .yourModels: String(localized: "Your models")
        case .verified: String(localized: "Verified")
        }
    }
}

/// Experimental models stay available but collapsed, so the table opens with
/// models Airdraft has tested. Searching includes them without a click.
struct ExperimentalModelsDisclosure: View {
    let count: Int
    var kept = 0
    let expanded: Bool
    let searching: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Experimental models (\(count))").appFont(.body, weight: .medium)
                    Text(searching ? String(localized: "Search results include experimental models.")
                         : kept > 0 ? String(localized: "Not yet tested end to end in Airdraft. Models you use or have downloaded stay listed.")
                         : String(localized: "Not yet tested end to end in Airdraft. They may fail to load or transcribe poorly."))
                        .supportingText().fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.cardPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!searching)
        .accessibilityLabel(Text("Experimental models (\(count))"))
        .accessibilityValue(expanded ? Text("Expanded") : Text("Collapsed"))
        .accessibilityHint(searching ? Text(verbatim: "") : Text("Shows or hides models Airdraft has not tested end to end."))
        .accessibilityIdentifier("models.experimental-disclosure")
    }
}

struct ModelRow: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.colorSchemeContrast) private var contrast
    let entry: ModelEntry
    /// Why the entry is in the compact recommended set, if it is.
    var role: LocalModelShortlist.Role?
    @State private var error: String?
    @State private var installed = false
    @State private var checkingInstallation = true
    @State private var hovering = false
    @State private var confirmDelete = false

    private var progress: ModelDownloader.Progress? { container.downloads.jobs[entryConfig.engineID]?.progress }
    private var downloadError: String? { container.downloads.jobs[entryConfig.engineID]?.error }

    private var entryConfig: ASRConfig { entry.config(from: container.settings.asr) }
    private var isSelectedForUse: Bool {
        entry.isSelected(container.settings.asr) || entry.isSelected(container.speechConfig)
    }

    var body: some View {
        @Bindable var settings = container.settings
        #if DEBUG
        let _ = ModelsPerformanceVerification.noteRow(entry.id)
        #endif
        let selected = entry.isSelected(settings.asr)
        VStack(alignment: .leading, spacing: 6) {
            ModelComparisonColumns {
                Button {
                    guard installed else { return }
                    entry.select(&settings.asr)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14))
                            .foregroundStyle(selected ? Color.accentColor
                                             : Color.secondary.opacity(contrast == .increased ? 1 : installed ? 0.6 : 0.3))
                        ModelBrandIcon(brand: entry.brand)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title).appFont(.body, weight: .medium)
                            // One visible label: why the model is recommended, or
                            // its strength elsewhere in the table.
                            if let label = strengthLabel {
                                Text("\(Image(systemName: label.symbol)) \(label.text)")
                                    .appFont(.supporting, weight: .medium)
                                    .mutedForeground(0.75)
                            }
                            tierAndTags
                            loadStateLabel
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(selected ? "Selected" : "Not selected")
                .help("\(entry.vendor). \(entry.note) \(installed ? String(localized: "Use this model") : String(localized: "Download first"))")
            } speed: {
                ModelMetric(title: String(localized: "Speed"), fraction: entry.speed > 0 ? Double(entry.speed) / 5 : nil, label: entry.speed > 0 ? "\(entry.speed) / 5" : String(localized: "Not rated"),
                            detail: entry.speed > 0 ? String(localized: "Airdraft's relative guidance for local models. Actual speed depends on your Mac.") : String(localized: "Not benchmarked in Airdraft."))
            } accuracy: {
                ModelMetric(title: String(localized: "Accuracy"), fraction: entry.accuracy > 0 ? Double(entry.accuracy) / 5 : nil, label: entry.accuracy > 0 ? "\(entry.accuracy) / 5" : String(localized: "Not rated"),
                            detail: (entry.accuracy > 0 ? String(localized: "Airdraft's relative guidance for local models.")
                                     : String(localized: "Not benchmarked in Airdraft.")) + " " + entry.note)
            } cost: {
                storageLabel
            } accessory: {
                actions
            }
            if let progress {
                ModelDownloadProgress(progress: progress).padding(.leading, 56)
            }
            if let error = error ?? downloadError {
                Text(error).appFont(.annotation).foregroundStyle(.orange).padding(.leading, 56)
            }
        }
        .padding(Theme.cardPadding)
        .background(selected ? Color.primary.opacity(0.06) : (hovering ? Color.primary.opacity(0.03) : .clear))
        .onHover { hovering = $0 }
        .help(entry.note)
        .task(id: progress != nil) {
            checkingInstallation = true
            let config = entryConfig
            let result = await Task.detached(priority: .utility) { LocalModels.isInstalled(config) }.value
            guard !Task.isCancelled else { return }
            installed = result
            checkingInstallation = false
        }
    }

    private var strengthLabel: (symbol: String, text: String)? {
        if let role { return role.label(for: ModelCatalogue.recommendation.reason) }
        return entry.highlight.map { ("star.fill", $0) }
    }

    /// Tier first, as a compact symbol and word, then the languages by name and
    /// runtime tags. The tooltip lists every supported language.
    private var tierAndTags: some View {
        let details = ([entry.languageSummary] + entry.tags).joined(separator: " · ")
        return Group {
            if let tier = entry.tier {
                Text("\(Image(systemName: tier.symbol)) \(tier.title) · \(details)")
            } else {
                Text(details)
            }
        }
        .supportingText()
        .fixedSize(horizontal: false, vertical: true)
        .help([entry.tier?.detail, entry.languageDetail].compactMap { $0 }.joined(separator: " "))
    }

    private var accessibilityLabel: String {
        var parts = [String(localized: "Use \(entry.title)"), entry.provider]
        if let label = strengthLabel { parts.append(label.text) }
        if let tier = entry.tier { parts.append(tier.title) }
        parts.append(entry.languageSummary)
        parts += entry.tags
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var loadStateLabel: some View {
        if entry.isDownloadable, installed {
            switch container.engineStatus.state(for: entryConfig.engineID) {
            case .ready:
                HStack(spacing: 5) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("In memory").appFont(.annotation).foregroundStyle(.secondary)
                }
                .help(container.settings.idleUnloadMinutes == 0
                    ? "Loaded in RAM. Stays loaded until you unload it, switch models, or quit the app."
                    : "Loaded in RAM. Unloads after \(container.settings.idleUnloadMinutes) idle minutes, when you switch models, or when the app quits.")
            case .loading:
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text("Loading…").appFont(.annotation).foregroundStyle(.secondary)
                }
            case .failed(let message):
                Text("Load failed").appFont(.annotation).foregroundStyle(.orange).help(message)
            case .notLoaded:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var storageLabel: some View {
        switch entry.storage {
        case .download(let size):
            Text(size).appFont(.detail).foregroundStyle(.secondary).monospacedDigit()
        case .builtIn:
            Text("Built in").appFont(.detail).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if progress != nil {
            Button { container.downloads.cancel(entryConfig) } label: {
                Image(systemName: "xmark.circle").font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Cancel download")
            .accessibilityLabel("Cancel download of \(entry.title)")
        } else if checkingInstallation {
            ProgressView().controlSize(.mini).accessibilityLabel("Checking \(entry.title)")
        } else if !installed, entry.isDownloadable {
            Button { download() } label: {
                Image(systemName: "arrow.down.circle").font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .help("Download")
            .accessibilityLabel("Download \(entry.title)")
        } else if installed, LocalModels.folder(for: entryConfig) != nil {
            Button { confirmDelete = true } label: { Image(systemName: "trash").font(.system(size: 13)) }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(isSelectedForUse ? "Choose another model in Models or the active profile before deleting this one" : "Delete downloaded files")
            .accessibilityLabel("Delete \(entry.title)")
            .disabled(isSelectedForUse || container.pipeline.isBusy || container.engineStatus.hasPendingLoad(for: entryConfig.engineID))
            .confirmationDialog("Delete \(entry.title)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteFiles() }
            } message: {
                Text(storageMessage)
            }
        } else {
            Color.clear.frame(width: 16, height: 16)
        }
    }

    private var storageMessage: String {
        if case .download(let size) = entry.storage { return String(localized: "Frees \(size). You can download it again later.") }
        return String(localized: "You can download it again later.")
    }

    private func deleteFiles() {
        guard !isSelectedForUse, !container.pipeline.isBusy,
              !container.engineStatus.hasPendingLoad(for: entryConfig.engineID) else { return }
        do {
            try LocalModels.remove(entryConfig)
            error = nil
        } catch {
            self.error = String(localized: "Could not delete the model files: \(error.localizedDescription)")
        }
        installed = LocalModels.isInstalled(entryConfig)
    }

    private func download() {
        let config = entryConfig
        let originalSelection = container.settings.asr
        let followedAppDefault = container.profiles.activeProfile.speechModel == nil
        error = nil
        container.downloads.start(config) {
            // Completing a background download must not override a newer choice.
            if followedAppDefault, container.profiles.activeProfile.speechModel == nil,
               container.settings.asr == originalSelection {
                entry.select(&container.settings.asr)
            }
            if container.speechConfig.engineID == config.engineID {
                container.models.loadSpeechModel()
            }
        }
    }
}
