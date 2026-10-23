import AirdraftCore
import AppKit
import SwiftUI

/// Home's centrepiece: the four headline metrics in one row above the icon's
/// pressed-in capsule, drawn from the user's own dictations.
struct HomeHero: View {
    let overview: HistoryStore.Overview
    let periodTitle: String
    let hotkey: Hotkey
    let behavior: HotkeyBehavior
    var triggerDelayMilliseconds = 0
    var canDictate = true
    /// History decides between metrics and a headline. Before the first saved
    /// dictation the metrics would all read zero, so the hero explains what fills
    /// it; an unreadable History is never shown as a first run.
    var content: HomeHistoryContent = .metrics
    private var isReady: Bool { content != .loading }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pointer: CGFloat?
    @State private var hoveredIndex: Int?
    @State private var selectedID = RenderMode.value("HERO_SELECTED_ID").flatMap(Int64.init)
    @FocusState private var focusedPulseID: Int64?
    @State private var grown = RenderMode.isActive
    @State private var flare = 0.0

    private nonisolated static let caretWidth: CGFloat = 5
    private nonisolated static let caretGap: CGFloat = 10
    private static let wellHeight: CGFloat = 60
    private nonisolated static let wellHorizontalInset: CGFloat = 24
    /// The tallest bar: two thirds of the original hero's, so the metrics lead.
    private static let barMax: CGFloat = 32
    private static let caretHeight: CGFloat = 38

    var body: some View {
        VStack(spacing: Theme.sectionSpacing) {
            if content == .firstDictation {
                firstRunHeadline
            } else if content == .unavailable {
                unavailableHeadline
            } else {
                HStack(alignment: .top, spacing: Theme.controlSpacing) {
                    HeroMetric(value: stats.wordsPerMinute.formatted(), unit: String(localized: "WPM"), label: "Average speed")
                    HeroMetric(value: stats.words.formatted(), label: "Words")
                    HeroMetric(value: stats.apps.formatted(), label: "Apps used")
                    HeroMetric(value: saved.value, unit: saved.unit, label: "Saved \(periodTitle.lowercased())")
                        .help("Compared with typing the same words at 40 WPM")
                }
                // History decides between metrics and the first-run headline; never flash zeros.
                .opacity(isReady ? 1 : 0)
            }
            VStack(spacing: Theme.controlSpacing) {
                waveform
                caption.frame(height: 20)
            }
            if let selectedPulse {
                HomeHeroTranscript(pulse: selectedPulse) { closeTranscript() }
                    .id(selectedPulse.id)
                    .transition(.opacity)
            }
        }
        .padding(Theme.pagePadding)
        .frame(maxWidth: .infinity)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(border)
        .background(castShadows)
        .onChange(of: periodTitle) { _, _ in
            select(nil)
            hoveredIndex = nil
            pointer = nil
        }
        .onChange(of: overview.pulses.map(\.id)) { _, ids in
            hoveredIndex = nil
            pointer = nil
            if let selectedID, !ids.contains(selectedID) { select(nil) }
        }
        .onKeyPress(.escape) {
            guard selectedID != nil else { return .ignored }
            closeTranscript()
            return .handled
        }
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

    /// Same height as the metric row, so the hero keeps its shape after the first dictation.
    private var firstRunHeadline: some View {
        VStack(alignment: .leading, spacing: 4) {
            (canDictate ? Text("Ready for your first dictation") : Text("Almost ready to dictate"))
                .appFont(.title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("Your speed, words and time saved appear here after you dictate.")
                .appFont(.detail)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("home.first-run")
    }

    /// Same height as the metric row. The notice below the hero offers Reload History.
    private var unavailableHeadline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("History unavailable")
                .appFont(.title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("Your speed, words and time saved return when History can be read.")
                .appFont(.detail)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("home.history-unavailable")
    }

    private var selectedPulse: HistoryStore.Overview.Pulse? {
        overview.pulses.first { $0.id == selectedID }
    }

    private func select(_ id: Int64?) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { selectedID = id }
    }

    private func closeTranscript() {
        focusedPulseID = selectedID
        select(nil)
    }

    private var saved: (value: String, unit: String) {
        let minutes = stats.minutesSaved
        if minutes >= 60 { return ((Double(minutes) / 60).formatted(.number.precision(.fractionLength(1))),
                                     String(localized: "h", comment: "Hours unit after a number")) }
        return (minutes.formatted(), String(localized: "min", comment: "Minutes unit after a number"))
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
            return Bar(id: "record-\(pulse.id)", height: 0.26 + 0.74 * share, pulse: pulse)
        }
    }

    private struct Layout {
        let step: CGFloat
        let barWidth: CGFloat
        let startX: CGFloat

        init(size: CGSize, count: Int) {
            // Leave room for the rounded ends while bringing the bars closer to the rim.
            let inner = size.width - HomeHero.wellHorizontalInset * 2
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
                    if let pulse = bar.pulse {
                        let selected = pulse.id == selectedID
                        Button { select(selected ? nil : pulse.id) } label: {
                            barView(bar, index: index, layout: layout, hovered: hovered == index || selected)
                                .frame(height: Self.wellHeight)
                                .contentShape(Rectangle())
                                .overlay(alignment: .bottom) {
                                    if selected {
                                        Circle().fill(.primary.opacity(0.65))
                                            .frame(width: 3, height: 3)
                                            .padding(.bottom, 6)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .focused($focusedPulseID, equals: pulse.id)
                        .accessibilityLabel("\(pulse.appName ?? String(localized: "Unknown app")), \(pulse.date.formatted(date: .abbreviated, time: .shortened))")
                        .accessibilityValue("\(pulse.words) words, \(pulse.wordsPerMinute) WPM, \(selected ? String(localized: "expanded") : String(localized: "collapsed"))")
                        .accessibilityHint(selected ? "Hide this dictation's text" : "Show this dictation's text")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("home.dictation.\(pulse.id)")
                    } else {
                        barView(bar, index: index, layout: layout, hovered: false)
                            .accessibilityHidden(true)
                    }
                }
                caret
                    .padding(.leading, Self.caretGap)
                    .accessibilityHidden(true)
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
                        .appFont(.caption, weight: .medium).monospacedDigit()
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .position(x: layout.center(of: hovered), y: -10)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: Self.wellHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dictation activity")
        .accessibilityValue(defaultCaption)
    }

    /// A raised pill standing in the pressed well: lit from the top left,
    /// shadowed to the bottom right, as in the app icon. Every bar stays gray;
    /// the hovered one deepens toward the caret's tone.
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
            .fill(LinearGradient(colors: [soft.raisedTop.mix(with: soft.caretTop, by: tint),
                                          soft.raisedBottom.mix(with: soft.caretBottom, by: tint)],
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

    /// A raised gray pill, a step stronger than the bars, lit from the top left.
    /// A new dictation lifts it briefly; it never takes a colour or a glow.
    private var caret: some View {
        let shape = RoundedRectangle(cornerRadius: Self.caretWidth / 2, style: .continuous)
        return shape
            .fill(LinearGradient(colors: [soft.caretTop, soft.caretBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(shape.strokeBorder(LinearGradient(colors: [soft.rim, soft.rim.opacity(0)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75))
            .background {
                SurfaceShadows(shape: shape, shadows: [
                    .init(color: soft.shade, radius: 2.5 + 2 * flare, x: 1.5 + flare, y: 2.5 + 1.5 * flare),
                    .init(color: soft.light, radius: 2 + flare, x: -1, y: -1.5),
                ])
            }
            .frame(width: Self.caretWidth, height: Self.caretHeight)
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
        if pulses < total { return String(localized: "Latest \(pulses) of \(total.formatted()) dictations") }
        return total == 1 ? String(localized: "1 dictation · \(periodTitle.lowercased())")
            : String(localized: "\(total.formatted()) dictations · \(periodTitle.lowercased())")
    }

    @ViewBuilder private var caption: some View {
        let bars = self.bars
        let pulse = hoveredIndex.flatMap { bars.indices.contains($0) ? bars[$0].pulse : nil } ?? selectedPulse
        Group {
            if let pulse {
                HStack(spacing: 6) {
                    Text(pulse.appName ?? String(localized: "Unknown app")).foregroundStyle(.primary)
                    Text("·")
                    Text("\(pulse.words.formatted()) words")
                    if pulse.wordsPerMinute > 0 {
                        Text("·")
                        Text("\(pulse.wordsPerMinute) WPM")
                    }
                }
            } else if overview.pulses.isEmpty && !canDictate {
                content == .firstDictation ? Text("Complete setup below before your first dictation.")
                    : Text("Resolve the items below to dictate.")
            } else if overview.pulses.isEmpty {
                HStack(spacing: 6) {
                    Text(behavior.instructionVerb(triggerDelayMilliseconds: triggerDelayMilliseconds))
                    KeyCaps(hotkey: hotkey)
                    Text("and speak. Each dictation adds a bar.")
                }
            } else {
                Text("\(defaultCaption) · Click a bar to read")
            }
        }
        .appFont(.detail).monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    // MARK: Surface

    private var surface: some View {
        ZStack {
            LinearGradient(colors: [soft.surfaceTop, soft.surfaceBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [soft.light.opacity(0.2), soft.light.opacity(0)],
                           center: UnitPoint(x: 0.15, y: 0), startRadius: 0, endRadius: 420)
        }
    }

    /// The raised card catches the top-left light and casts its shade down-right.
    private var castShadows: some View {
        SurfaceShadows(shape: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous), shadows: [
            .init(color: soft.shade.opacity(scheme == .dark ? 0.7 : 0.85), radius: 12, x: 7, y: 9),
            .init(color: soft.light, radius: 12, x: -6, y: -7),
        ])
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            // A faint edge: the cast shadows carry the card's depth.
            .strokeBorder(LinearGradient(colors: [soft.rim.opacity(0.3), soft.rim.opacity(0)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    // Increase Contrast adds an explicit edge, like the cards and controls.
                    .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.35 : 0.035), lineWidth: 0.5)
            )
    }
}

/// The selected dictation stays part of the hero, with the same bounded,
/// selectable text used in History. Changing bars resets expansion and Copy.
private struct HomeHeroTranscript: View {
    let pulse: HistoryStore.Overview.Pulse
    let onClose: () -> Void
    private let content: HistoryTextContent
    @State private var expanded = false
    @State private var copied = false

    init(pulse: HistoryStore.Overview.Pulse, onClose: @escaping () -> Void) {
        self.pulse = pulse
        self.onClose = onClose
        content = HistoryTextContent(pulse.finalText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.controlSpacing) {
            RowDivider()
            HStack(spacing: Theme.controlSpacing) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pulse.appName ?? String(localized: "Unknown app"))
                        .appFont(.body, weight: .medium)
                        .lineLimit(1)
                    Text(pulse.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .supportingText()
                }
                Spacer(minLength: Theme.controlSpacing)
                Button {
                    NSPasteboard.general.clearContents()
                    copied = NSPasteboard.general.setString(pulse.finalText, forType: .string)
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(SoftIconButtonStyle())
                .disabled(content.full.isEmpty)
                .help(copied ? "Copied" : "Copy Text")
                .accessibilityLabel(copied ? "Copied" : "Copy Text")
                .accessibilityIdentifier("home.dictation.copy")
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(SoftIconButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .help("Close Transcript")
                    .accessibilityLabel("Close Transcript")
                    .accessibilityIdentifier("home.dictation.close")
            }
            if content.full.isEmpty {
                EmptyNote("No text was saved for this dictation.")
            } else {
                HistoryTranscript(content: content, expanded: $expanded)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dictation transcript")
        .accessibilityIdentifier("home.dictation.transcript")
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}

/// Neutral soft-UI colours: one surface, a pressed well, raised bars, and the
/// light and shade that give them depth.
private struct SoftPalette {
    let surfaceTop, surfaceBottom, well, raisedTop, raisedBottom, caretTop, caretBottom, light, shade, rim: Color

    init(dark: Bool) {
        if dark {
            // A gentle ramp just above the 0.15 island; depth comes from the shadows.
            surfaceTop = Color(white: 0.19)
            surfaceBottom = Color(white: 0.17)
            well = Color(white: 0.14)
            raisedTop = Color(white: 0.34)
            raisedBottom = Color(white: 0.22)
            caretTop = Color(white: 0.62)
            caretBottom = Color(white: 0.42)
            light = .white.opacity(0.09)
            shade = .black.opacity(0.75)
            rim = .white.opacity(0.16)
        } else {
            // Mid-tone on the 0.90 island, leaving the white highlight room to show.
            surfaceTop = Color(white: 0.91)
            surfaceBottom = Color(white: 0.89)
            well = Color(white: 0.85)
            raisedTop = Color(white: 0.79)
            raisedBottom = Color(white: 0.54)
            caretTop = Color(white: 0.52)
            caretBottom = Color(white: 0.30)
            light = .white
            shade = .black.opacity(0.32)
            rim = .white.opacity(0.9)
        }
    }
}

/// A headline number with its unit and label; the hero gives each one an equal column.
struct HeroMetric: View {
    let value: String
    var unit: String? = nil
    let label: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .appFont(.metric)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .appFont(.body, weight: .semibold, design: .rounded)
                        .foregroundStyle(.secondary)
                }
            }
            Text(label)
                .appFont(.detail)
                .foregroundStyle(.secondary)
                // Wraps rather than truncates at larger text sizes (已節省（全部時間）).
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
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
    HomeHero(overview: .empty, periodTitle: "All time", hotkey: .controlOption, behavior: .hold, content: .firstDictation)
        .padding(Theme.pagePadding)
        .frame(width: 720)
}
#endif
