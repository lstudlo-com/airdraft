import AirdraftCore
import SwiftUI

/// The app icon's waveform and caret colours.
enum Brand {
    static let violet = Color(red: 0.420, green: 0.478, blue: 1.000)   // #6B7AFF
    static let cyan = Color(red: 0.231, green: 0.765, blue: 0.957)     // #3BC3F4

    static var gradient: LinearGradient {
        LinearGradient(colors: [violet, cyan], startPoint: .top, endPoint: .bottom)
    }
}

/// Home's centrepiece: the four headline metrics in one row above the icon's
/// pressed-in capsule, drawn from the user's own dictations.
struct HomeHero: View {
    let overview: HistoryStore.Overview
    let periodTitle: String
    let hotkey: Hotkey
    let behavior: HotkeyBehavior
    var isReady = true
    var canDictate = true

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pointer: CGFloat?
    @State private var hoveredIndex: Int?
    @State private var grown = RenderMode.isActive
    @State private var flare = 0.0

    private static let caretWidth: CGFloat = 5
    private static let caretGap: CGFloat = 10
    private static let wellHeight: CGFloat = 84
    /// The tallest bar: two thirds of the original hero's, so the metrics lead.
    private static let barMax: CGFloat = 32
    private static let caretHeight: CGFloat = 38

    var body: some View {
        VStack(spacing: Theme.sectionSpacing) {
            HStack(alignment: .top, spacing: Theme.controlSpacing) {
                HeroMetric(value: stats.wordsPerMinute.formatted(), unit: "WPM", label: "Average speed")
                HeroMetric(value: stats.words.formatted(), label: "Words")
                HeroMetric(value: stats.apps.formatted(), label: "Apps used")
                HeroMetric(value: saved.value, unit: saved.unit, label: "Saved \(periodTitle.lowercased())")
                    .help("Compared with typing the same words at 40 WPM")
            }
            VStack(spacing: Theme.controlSpacing) {
                waveform
                caption.frame(height: 20)
            }
        }
        .padding(Theme.pagePadding)
        .frame(maxWidth: .infinity)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(border)
        .task(id: isReady) {
            guard isReady, !grown else { return }
            // Give the loaded bars their own initial layout before revealing
            // them. The entrance changes rendered scale, never layout height.
            await Task.yield()
            guard !Task.isCancelled else { return }
            grown = true
        }
        .onChange(of: overview.pulses.last?.date) { old, new in
            guard let new, let old, new > old, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.25)) { flare = 1 } completion: {
                withAnimation(.smooth(duration: 1.6)) { flare = 0 }
            }
        }
    }

    private var stats: HistoryStore.Stats { overview.stats }

    private var saved: (value: String, unit: String) {
        let minutes = stats.minutesSaved
        if minutes >= 60 { return ((Double(minutes) / 60).formatted(.number.precision(.fractionLength(1))), "h") }
        return (minutes.formatted(), "min")
    }

    // MARK: Waveform

    private struct Bar: Identifiable {
        let id: String
        /// Resting height as a fraction of `barMax`.
        let height: CGFloat
        let pulse: HistoryStore.Overview.Pulse?
    }

    private var bars: [Bar] {
        let pulses = overview.pulses
        guard !pulses.isEmpty else {
            // The icon's five strokes, waiting for a first dictation.
            return [0.36, 0.66, 1.0, 0.72, 0.48].enumerated().map { index, height in
                Bar(id: "empty-\(index)", height: height, pulse: nil)
            }
        }
        let most = Double(pulses.map(\.words).max() ?? 1)
        return pulses.map { pulse in
            let share = most > 0 ? sqrt(Double(pulse.words) / most) : 0
            return Bar(id: "\(pulse.date.timeIntervalSinceReferenceDate)", height: 0.26 + 0.74 * share, pulse: pulse)
        }
    }

    private struct Layout {
        let step: CGFloat
        let barWidth: CGFloat
        let startX: CGFloat

        init(size: CGSize, count: Int) {
            // The capsule's rounded ends take roughly its height.
            let inner = size.width - size.height * 1.1
            let available = inner - HomeHero.caretGap - HomeHero.caretWidth
            step = min(18, max(4, available / CGFloat(max(count, 1))))
            barWidth = min(7, max(3, step * 0.5))
            let group = step * CGFloat(count) + HomeHero.caretGap + HomeHero.caretWidth
            startX = (size.width - group) / 2
        }

        func index(at x: CGFloat, count: Int) -> Int? {
            let i = Int(((x - startX) / step).rounded(.down))
            return (0..<count).contains(i) ? i : nil
        }

        func center(of index: Int) -> CGFloat { startX + step * (CGFloat(index) + 0.5) }
    }

    private var waveform: some View {
        let bars = self.bars
        return GeometryReader { geo in
            let layout = Layout(size: geo.size, count: bars.count)
            let hovered = hoveredIndex.flatMap { bars.indices.contains($0) ? $0 : nil }
            HStack(spacing: 0) {
                ForEach(Array(bars.enumerated()), id: \.element.id) { index, bar in
                    barView(bar, index: index, layout: layout, hovered: hovered == index)
                }
                caret
                    .padding(.leading, Self.caretGap)
            }
            .opacity(isReady ? 1 : 0)
            .frame(width: geo.size.width, height: geo.size.height)
            .background(well)
            .contentShape(Capsule())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    pointer = location.x
                    hoveredIndex = layout.index(at: location.x, count: bars.count)
                case .ended:
                    pointer = nil
                    hoveredIndex = nil
                }
            }
            .overlay(alignment: .top) {
                if let hovered, let pulse = bars[hovered].pulse {
                    Text(pulse.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .position(x: layout.center(of: hovered), y: -10)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: Self.wellHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dictation activity")
        .accessibilityValue(defaultCaption)
    }

    /// A raised pill standing in the pressed well: lit from the top left,
    /// shadowed to the bottom right, as in the app icon. Bars stay neutral;
    /// only the hovered one takes the icon's violet-to-cyan.
    private func barView(_ bar: Bar, index: Int, layout: Layout, hovered: Bool) -> some View {
        let magnify: CGFloat = {
            guard let pointer, !reduceMotion, bar.pulse != nil else { return 1 }
            let distance = (layout.center(of: index) - pointer) / (layout.step * 2.4)
            return 1 + 0.28 * exp(-distance * distance)
        }()
        let tint = hovered ? 0.9 : 0
        let height = Self.barMax * bar.height
        let hoverScale = min(Self.caretHeight / height, magnify)
        return Capsule()
            .fill(LinearGradient(colors: [soft.raisedTop.mix(with: Brand.violet, by: tint),
                                          soft.raisedBottom.mix(with: Brand.cyan, by: tint)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                Capsule().strokeBorder(LinearGradient(colors: [soft.rim, soft.rim.opacity(0)],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
            )
            .background {
                SurfaceShadows(shape: Capsule(), shadows: [
                    .init(color: soft.shade, radius: 2.5, x: 1.5, y: 2.5),
                    .init(color: soft.light, radius: 2, x: -1, y: -1.5),
                ])
            }
            .frame(width: layout.barWidth, height: height)
            .scaleEffect(y: reduceMotion || grown ? 1 : 0.12)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.45).delay(min(Double(index) * 0.003, 0.12)), value: grown)
            .scaleEffect(y: hoverScale)
            .animation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.15), value: hoverScale)
            .frame(width: layout.step)
            .transition(.identity)
    }

    private var caret: some View {
        RoundedRectangle(cornerRadius: Self.caretWidth / 2, style: .continuous)
            .fill(Brand.gradient)
            .frame(width: Self.caretWidth, height: Self.caretHeight)
            .shadow(color: Brand.violet.opacity(0.45 + 0.4 * flare), radius: 8 + 12 * flare)
            .scaleEffect(y: 1 + 0.08 * flare)
    }

    /// The pressed-in track: shade inside the top-left edge, light inside the bottom-right.
    private var well: some View {
        Capsule()
            .fill(soft.well
                .shadow(.inner(color: soft.shade, radius: 6, x: 4, y: 5))
                .shadow(.inner(color: soft.light, radius: 6, x: -4, y: -5)))
            .overlay(
                Capsule().strokeBorder(LinearGradient(colors: [soft.shade.opacity(0.35), .clear, soft.light],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
    }

    /// Grayscale soft-UI colours for the current appearance.
    private var soft: SoftPalette { SoftPalette(dark: scheme == .dark) }

    // MARK: Caption

    private var defaultCaption: String {
        let pulses = overview.pulses.count
        let total = stats.dictations
        if pulses < total { return "Latest \(pulses) of \(total.formatted()) dictations" }
        return "\(total.formatted()) \(total == 1 ? "dictation" : "dictations") · \(periodTitle.lowercased())"
    }

    @ViewBuilder private var caption: some View {
        let bars = self.bars
        Group {
            if let index = hoveredIndex, bars.indices.contains(index), let pulse = bars[index].pulse {
                HStack(spacing: 6) {
                    Text(pulse.appName ?? "Unknown app").foregroundStyle(.primary)
                    Text("·")
                    Text("\(pulse.words.formatted()) words")
                    if pulse.wordsPerMinute > 0 {
                        Text("·")
                        Text("\(pulse.wordsPerMinute) WPM")
                    }
                }
            } else if overview.pulses.isEmpty && !canDictate {
                Text("Complete setup below before your first dictation.")
            } else if overview.pulses.isEmpty {
                HStack(spacing: 6) {
                    Text(behavior.instructionVerb)
                    KeyCaps(hotkey: hotkey)
                    Text("and speak. Each dictation adds a bar.")
                }
            } else {
                Text(defaultCaption)
            }
        }
        .font(.system(size: 12).monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    // MARK: Surface

    private var surface: some View {
        ZStack {
            LinearGradient(colors: [soft.surfaceTop, soft.surfaceBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [soft.light.opacity(0.5), soft.light.opacity(0)],
                           center: UnitPoint(x: 0.15, y: 0), startRadius: 0, endRadius: 420)
        }
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            .strokeBorder(LinearGradient(colors: [soft.rim, soft.rim.opacity(0)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
            )
    }
}

/// Neutral soft-UI colours: one surface, a pressed well, raised bars, and the
/// light and shade that give them depth.
private struct SoftPalette {
    let surfaceTop, surfaceBottom, well, raisedTop, raisedBottom, light, shade, rim: Color

    init(dark: Bool) {
        if dark {
            surfaceTop = Color(white: 0.2)
            surfaceBottom = Color(white: 0.16)
            well = Color(white: 0.14)
            raisedTop = Color(white: 0.34)
            raisedBottom = Color(white: 0.22)
            light = .white.opacity(0.09)
            shade = .black.opacity(0.75)
            rim = .white.opacity(0.16)
        } else {
            surfaceTop = Color(white: 0.955)
            surfaceBottom = Color(white: 0.9)
            well = Color(white: 0.9)
            raisedTop = Color(white: 0.97)
            raisedBottom = Color(white: 0.8)
            light = .white
            shade = .black.opacity(0.28)
            rim = .white.opacity(0.9)
        }
    }
}

/// A headline number with its unit and label; the hero gives each one an equal column.
struct HeroMetric: View {
    let value: String
    var unit: String? = nil
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Hero") {
    HomeHero(overview: PreviewData.overview(), periodTitle: "All time", hotkey: .controlOption, behavior: .hold)
        .padding(Theme.pagePadding)
        .frame(width: 720)
}

#Preview("Hero · first run") {
    HomeHero(overview: .empty, periodTitle: "All time", hotkey: .controlOption, behavior: .hold)
        .padding(Theme.pagePadding)
        .frame(width: 720)
}
#endif
