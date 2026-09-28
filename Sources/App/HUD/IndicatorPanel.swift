import AppKit
import AirdraftCore
import QuartzCore
import SwiftUI
import os

/// Content-sized recording HUD. Never takes focus, so the target app keeps its cursor.
@MainActor
final class IndicatorPanelController {
    private let panel: NSPanel
    private let pipeline: DictationPipeline
    private let styleProvider: () -> HUDStyle
    private var hideTask: Task<Void, Never>?
    private var currentStyle: HUDStyle = .classic
    private var currentPreview = false
    private var lastVisibleState: PipelineState = .idle
    private var dismissalID: UUID?
    private var contentID = UUID()

    init(pipeline: DictationPipeline, style: @escaping () -> HUDStyle) {
        self.pipeline = pipeline
        self.styleProvider = style
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        applyStyle(.classic, preview: false)
    }

    private func applyStyle(_ style: HUDStyle, preview: Bool) {
        currentStyle = style
        currentPreview = preview
        let id = UUID()
        contentID = id
        let host = NSHostingView(rootView: RecordingHUDView(pipeline: pipeline, style: style, showPreview: preview,
            onSizeChange: { [weak self] size in
                guard let self, self.contentID == id, self.dismissalID == nil else { return }
                self.resize(to: size)
            }))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        panel.contentView = host
    }

    func update(for state: PipelineState) {
        switch state {
        case .idle:
            dismiss()
        case .failed, .notice:
            // Successful delivery already started the exit. Recovery details
            // remain on Home; late notices must not reopen the capsule.
            if case .notice = state, dismissalID != nil { return }
            cancelDismissal()
            lastVisibleState = state
            show()
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                self?.panel.orderOut(nil)
            }
        default:
            if state == .inserting, dismissalID != nil { return }
            cancelDismissal()
            lastVisibleState = state
            show()
        }
    }

    func deliveryCompleted() {
        dismiss()
    }

    private func cancelDismissal() {
        hideTask?.cancel()
        dismissalID = nil
        // Replaces an interrupted fade before showing a new recording.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
    }

    private func dismiss() {
        guard dismissalID == nil else { return }
        hideTask?.cancel()
        let id = UUID()
        dismissalID = id
        guard panel.isVisible else { return }

        // The live pipeline can move to idle while the panel is fading. Freeze
        // the final display so idle cannot bring back the recording timer.
        let snapshot = HUDSnapshot(state: lastVisibleState, levels: pipeline.levelHistory,
                                   elapsed: pipeline.lastRecordingDuration)
        let host = NSHostingView(rootView: RecordingHUDView(snapshot: snapshot, style: currentStyle,
            showPreview: currentPreview, sampleText: pipeline.previewIssue ?? pipeline.previewText))
        host.frame = NSRect(origin: .zero, size: panel.frame.size)
        panel.contentView = host

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.5
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.dismissalID == id else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    private static let log = Logger(subsystem: AppIdentity.logSubsystem, category: "hud")

    /// `NSScreen.main` is nil for a menu-bar app with no key window, so use the
    /// screen under the mouse, then the first screen.
    private var targetScreen: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func show() {
        let style = styleProvider()
        guard style != .none else {
            panel.orderOut(nil)
            return
        }
        let preview = pipeline.isRecording && pipeline.previewEnabledForRecording
        applyStyle(style, preview: preview)
        guard let content = panel.contentView else { return }
        resize(to: content.fittingSize)
        panel.orderFrontRegardless()
        Self.log.notice("HUD shown at \(NSStringFromRect(self.panel.frame), privacy: .public) visible=\(self.panel.isVisible, privacy: .public)")
    }

    private func resize(to size: CGSize) {
        guard size.width > 0, size.height > 0, let screen = targetScreen else { return }
        let frame = NSRect(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.minY + 18,
            width: size.width,
            height: size.height
        )
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }
}

/// Preview remains nonactivating and separate from the final transcript.
struct RecordingHUDView: View {
    var pipeline: DictationPipeline?
    var snapshot: HUDSnapshot?
    var style: HUDStyle
    var showPreview: Bool
    var sampleText: String?
    var onSizeChange: ((CGSize) -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            if showPreview {
                Text(pipeline?.previewIssue ?? sampleText ?? (pipeline?.previewText).flatMap { $0.isEmpty ? nil : $0 } ?? "Listening…")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .lineLimit(3)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .frame(width: 360, height: 76)
                    .background {
                        NeumorphicSurface(shape: RoundedRectangle(cornerRadius: 16, style: .continuous), depth: 1.5)
                    }
                    .environment(\.colorScheme, .dark)
            }
            if let pipeline { IndicatorView(pipeline: pipeline, style: style) }
            else if let snapshot { IndicatorView(snapshot: snapshot, style: style) }
        }
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSizeChange?($0) }
    }
}

extension PipelineState {
    /// Text the HUD shows instead of the waveform, if any.
    var hudMessage: String? {
        switch self {
        case .failed(let m), .notice(let m): return m
        default: return nil
        }
    }
}

/// Everything the HUD needs, decoupled from the pipeline so it can be rendered offscreen.
struct HUDSnapshot {
    var state: PipelineState
    var levels: [Float]
    var elapsed: TimeInterval
}

/// Dark pill with equal outer insets. Classic fits its current timer or status
/// label; Mini shows only the waveform.
struct IndicatorView: View {
    static let contentInset: CGFloat = 6

    var pipeline: DictationPipeline?
    var snapshot: HUDSnapshot?
    var style: HUDStyle = .classic

    init(pipeline: DictationPipeline, style: HUDStyle = .classic) { self.pipeline = pipeline; self.style = style }
    init(snapshot: HUDSnapshot, style: HUDStyle = .classic) { self.snapshot = snapshot; self.style = style }

    private var state: PipelineState { snapshot?.state ?? pipeline?.state ?? .idle }
    private var levels: [Float] { snapshot?.levels ?? pipeline?.levelHistory ?? [] }

    var body: some View {
        Group {
            if let message = state.hudMessage {
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 160, minHeight: 22)
            } else if style == .mini {
                waveform(width: 80, height: 14)
            } else {
                HStack(spacing: 8) {
                    waveform(width: 72, height: 16)
                    ElapsedTime(pipeline: pipeline, snapshot: snapshot)
                        .fixedSize()
                }
            }
        }
        .padding(Self.contentInset)
        .fixedSize()
        .background(
            Capsule(style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.10)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
        )
        .environment(\.colorScheme, .dark)
    }

    private func waveform(width: CGFloat, height: CGFloat) -> some View {
        WaveformBars(levels: levels, dimmed: state != .recording)
            .frame(width: width, height: height)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background { HUDWaveformWell() }
    }
}

/// A small, dark recess; live waveform bars keep their existing contrast.
private struct HUDWaveformWell: View {
    var body: some View {
        Capsule()
            .fill(Color(white: 0.08)
                .shadow(.inner(color: .black.opacity(0.65), radius: 2, x: 1, y: 1.5))
                .shadow(.inner(color: .white.opacity(0.10), radius: 2, x: -1, y: -1)))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Vertical capsules, newest on the right. White on the dark pill; dims while processing.
struct WaveformBars: View {
    let levels: [Float]
    let dimmed: Bool
    private let count = DictationPipeline.levelHistoryLength
    /// Quiet input still fills the pill: bars are drawn relative to the loudest
    /// of the visible samples. The floor keeps silence flat instead of amplifying
    /// room noise into a full-height waveform.
    private static let quietFloor: Float = 0.2

    var body: some View {
        GeometryReader { geo in
            let padded = Array(repeating: Float(0), count: max(0, count - levels.count)) + levels.suffix(count)
            let peak = max(Self.quietFloor, padded.max() ?? 0)
            let spacing: CGFloat = 2
            let barWidth = max(1.5, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(padded.enumerated()), id: \.offset) { _, level in
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(dimmed ? 0.28 : 0.92))
                        .frame(width: barWidth, height: max(2.5, CGFloat(shaped(level / peak)) * geo.size.height))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.linear(duration: 0.08), value: padded)
        }
    }

    private func shaped(_ level: Float) -> Float {
        min(1, pow(max(0, level), 0.7))
    }
}

struct ElapsedTime: View {
    var pipeline: DictationPipeline?
    var snapshot: HUDSnapshot?

    private var state: PipelineState { snapshot?.state ?? pipeline?.state ?? .idle }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let seconds = elapsed(at: context.date)
            if let caption {
                Text(caption)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text(format(seconds))
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(state == .recording ? 0.95 : 0.6))
            }
        }
    }

    private func elapsed(at date: Date) -> TimeInterval {
        if let snapshot { return snapshot.elapsed }
        guard let pipeline else { return 0 }
        if pipeline.state == .recording, let start = pipeline.recordingStartedAt {
            return date.timeIntervalSince(start)
        }
        return pipeline.lastRecordingDuration
    }

    private func format(_ t: TimeInterval) -> String {
        let total = max(0, t)
        let minutes = Int(total) / 60
        let seconds = Int(total) % 60
        let tenths = Int((total - floor(total)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }

    private var caption: String? {
        switch state {
        case .preparingModel: return "Loading"
        case .transcribing: return "Transcribing"
        case .refining: return "Refining"
        case .inserting: return "Inserting"
        default: return nil
        }
    }
}
