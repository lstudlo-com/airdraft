import AirdraftCore
import SwiftUI

/// AD-142: Home's dictation timing, between Summary and Recent. One stacked bar
/// shows how an average dictation divides into speaking, transcription and
/// refinement; each stage then gives its average and seconds per 100 words.
/// Advanced statistics list every speech and refinement model used in the period.
struct HomeStageCard: View {
    let stats: StageStatistics
    /// Renders open the table with `AIRDRAFT_RENDER_STAGE_DETAILS=1`.
    @State private var showsAdvanced = RenderMode.value("STAGE_DETAILS") != nil

    var body: some View {
        Card(spacing: Theme.controlSpacing) {
            StageBar(stats: stats)
            HStack(alignment: .top, spacing: Theme.controlSpacing) {
                ForEach(DictationStage.allCases) { stage in
                    StageFact(stage: stage, value: stats[stage], share: share(of: stage))
                }
            }
            RowDivider()
            DisclosureGroup(isExpanded: $showsAdvanced) {
                VStack(alignment: .leading, spacing: Theme.cardPadding) {
                    StageModelTable(title: "Speech models", models: stats.speechModels)
                    if !stats.refinementModels.isEmpty {
                        StageModelTable(title: "Refinement", models: stats.refinementModels)
                    }
                }
                .padding(.top, Theme.controlSpacing)
            } label: {
                Text(showsAdvanced ? "Hide Advanced Statistics" : "Show Advanced Statistics")
            }
            .settingsDisclosure()
        }
    }

    private func share(of stage: DictationStage) -> Double {
        let total = DictationStage.allCases.reduce(0) { $0 + stats[$1].averageSeconds }
        return total > 0 ? stats[stage].averageSeconds / total : 0
    }
}

enum DictationStage: CaseIterable, Identifiable {
    case speaking, transcription, refinement
    var id: Self { self }

    var title: String {
        switch self {
        case .speaking: String(localized: "Speaking")
        case .transcription: String(localized: "Transcription")
        case .refinement: String(localized: "Refinement")
        }
    }
}

extension StageStatistics {
    subscript(stage: DictationStage) -> Stage {
        switch stage {
        case .speaking: speaking
        case .transcription: transcription
        case .refinement: refinement
        }
    }
}

/// The three stages as one inset track holding raised segments. Each stage has
/// its own gray and texture (solid, hatched, dotted), so the parts stay
/// distinct without a hue, which the accent reserves for progress.
private struct StageBar: View {
    let stats: StageStatistics
    private let height: CGFloat = 14
    private let inset: CGFloat = 2
    private let gap: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            let stages = DictationStage.allCases.filter { stats[$0].averageSeconds > 0 }
            let total = stages.reduce(0) { $0 + stats[$1].averageSeconds }
            let available = max(0, geometry.size.width - inset * 2 - gap * CGFloat(max(0, stages.count - 1)))
            // A stage that ran stays visible even beside a much longer one.
            let minimum: CGFloat = 6
            let raw = stages.map { total > 0 ? CGFloat(stats[$0].averageSeconds / total) * available : 0 }
            let lifted = raw.map { max(minimum, $0) }
            let excess = lifted.reduce(0, +) - available
            let shrinkable = zip(raw, lifted).filter { $0.0 > minimum }.reduce(0) { $0 + $1.1 }
            HStack(spacing: gap) {
                ForEach(Array(stages.enumerated()), id: \.element) { index, stage in
                    let width = lifted[index] > minimum && shrinkable > 0
                        ? lifted[index] - excess * lifted[index] / shrinkable : lifted[index]
                    StageSwatch(stage: stage)
                        .frame(width: max(0, width))
                }
            }
            .padding(inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background { NeumorphicSurface(shape: Capsule(), inset: true, depth: 1.4) }
            .clipShape(Capsule())
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// One stage's fill, used in the bar and as the legend key.
struct StageSwatch: View {
    let stage: DictationStage
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let dark = scheme == .dark
        let shape = Capsule()
        shape.fill(tone(dark: dark))
            .overlay { texture(dark: dark).clipShape(shape) }
            .overlay {
                if contrast == .increased { shape.strokeBorder(Color.primary.opacity(0.5), lineWidth: 0.75) }
            }
            .background {
                SurfaceShadows(shape: shape, shadows: [
                    .init(color: .black.opacity(dark ? 0.55 : 0.22), radius: 1, x: 0.5, y: 0.8),
                    .init(color: .white.opacity(dark ? 0.1 : 0.85), radius: 1, x: -0.4, y: -0.5),
                ])
            }
    }

    /// Speaking is the darkest step in light mode and the brightest in dark
    /// mode; each later stage moves one step toward the track.
    private func tone(dark: Bool) -> Color {
        switch stage {
        case .speaking: Color(white: dark ? 0.66 : 0.42)
        case .transcription: Color(white: dark ? 0.48 : 0.60)
        case .refinement: Color(white: dark ? 0.32 : 0.76)
        }
    }

    @ViewBuilder private func texture(dark: Bool) -> some View {
        let ink = dark ? Color.white.opacity(0.22) : Color.black.opacity(0.16)
        switch stage {
        case .speaking:
            EmptyView()
        case .transcription:
            Canvas { context, size in
                var path = Path()
                var x = -size.height
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += 4
                }
                context.stroke(path, with: .color(ink), lineWidth: 1)
            }
        case .refinement:
            Canvas { context, size in
                var y: CGFloat = 1.5
                var row = 0
                while y < size.height {
                    var x: CGFloat = row.isMultiple(of: 2) ? 1.5 : 3.5
                    while x < size.width {
                        context.fill(Path(ellipseIn: CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5)), with: .color(ink))
                        x += 4
                    }
                    y += 2.5
                    row += 1
                }
            }
        }
    }
}

/// A stage's key, share, average and rate per 100 words.
private struct StageFact: View {
    let stage: DictationStage
    let value: StageStatistics.Stage
    let share: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                StageSwatch(stage: stage).frame(width: 16, height: 8)
                Text(stage.title).appFont(.annotation).foregroundStyle(.secondary)
                if value.dictations > 0 {
                    Text(share.formatted(.percent.precision(.fractionLength(0))))
                        .appFont(.annotation).monospacedDigit().foregroundStyle(.tertiary)
                }
            }
            Text(value.dictations > 0 ? DurationLabel.seconds(value.averageSeconds) : "—")
                .appFont(.statistic, weight: .semibold, design: .rounded)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(rate)
                .appFont(.supporting).monospacedDigit().foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isStaticText)
    }

    private var rate: String {
        guard value.dictations > 0 else { return String(localized: "Not used") }
        return value.secondsPer100Words.map(StageRate.label) ?? String(localized: "No words counted")
    }

    private var accessibilityText: String {
        guard value.dictations > 0 else { return "\(stage.title), " + String(localized: "Not used") }
        return [stage.title, share.formatted(.percent.precision(.fractionLength(0))),
                String(localized: "\(DurationLabel.seconds(value.averageSeconds)) on average"), rate]
            .joined(separator: ", ")
    }
}

enum StageRate {
    static func label(_ seconds: Double) -> String {
        String(localized: "\(DurationLabel.seconds(seconds)) per 100 words",
               comment: "Seconds a stage takes for every 100 words; the number 100 stays in the sentence")
    }
}

/// Every model used in the period with its own measured speed.
private struct StageModelTable: View {
    let title: LocalizedStringResource
    let models: [StageStatistics.Model]
    @Environment(\.textScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            columns {
                Text(title)
            } count: {
                Text("Dictations")
            } average: {
                Text("Average")
            } rate: {
                Text("Per 100 words")
            }
            .appFont(.detail, weight: .medium)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
            ForEach(models) { model in
                RowDivider()
                columns {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.name).appFont(.body, weight: .medium).lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let location = location(model) { Text(location).supportingText() }
                    }
                    .help(model.name == model.id ? model.id : "\(model.name)\n\(model.id)")
                } count: {
                    Text(model.stage.dictations.formatted()).appFont(.detail).monospacedDigit()
                } average: {
                    Text(DurationLabel.seconds(model.stage.averageSeconds)).appFont(.detail).monospacedDigit()
                } rate: {
                    Text(model.stage.secondsPer100Words.map { DurationLabel.seconds($0) } ?? "—")
                        .appFont(.detail).monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel([model.name, location(model) ?? "",
                                     String(localized: "\(model.stage.dictations) dictations"),
                                     String(localized: "\(DurationLabel.seconds(model.stage.averageSeconds)) on average"),
                                     model.stage.secondsPer100Words.map(StageRate.label) ?? ""]
                    .filter { !$0.isEmpty }.joined(separator: ", "))
            }
        }
    }

    /// Nil for rows saved before AD-142, which did not record where they ran.
    private func location(_ model: StageStatistics.Model) -> String? {
        model.onDevice.map { $0 ? String(localized: "On this Mac") : String(localized: "Cloud") }
    }

    private func columns<Name: View, Count: View, Average: View, Rate: View>(
        @ViewBuilder name: () -> Name, @ViewBuilder count: () -> Count,
        @ViewBuilder average: () -> Average, @ViewBuilder rate: () -> Rate) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.controlSpacing) {
            name().frame(maxWidth: .infinity, alignment: .leading)
            count().frame(width: 72 * scale, alignment: .trailing)
            average().frame(width: 60 * scale, alignment: .trailing)
            rate().frame(width: 96 * scale, alignment: .trailing)
        }
    }
}
