import AppKit
import AirdraftCore
import SwiftUI
import os

/// Minimal always-on-top HUD: waveform bars on the left (3/5), elapsed time on
/// the right (2/5). Never takes focus, so the target app keeps its cursor.
@MainActor
final class IndicatorPanelController {
    private let panel: NSPanel
    private let pipeline: DictationPipeline
    private let styleProvider: () -> HUDStyle
    private var hideTask: Task<Void, Never>?
    private var currentStyle: HUDStyle = .classic
    private var currentPreview = false

    init(pipeline: DictationPipeline, style: @escaping () -> HUDStyle) {
        self.pipeline = pipeline
        self.styleProvider = style
        let size = IndicatorView.size(for: .classic)
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
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
        let host = NSHostingView(rootView: RecordingHUDView(pipeline: pipeline, style: .classic, showPreview: false))
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
    }

    private func applyStyle(_ style: HUDStyle, preview: Bool) {
        guard style != currentStyle || preview != currentPreview else { return }
        currentStyle = style
        currentPreview = preview
        let size = RecordingHUDView.size(for: style, preview: preview)
        let host = NSHostingView(rootView: RecordingHUDView(pipeline: pipeline, style: style, showPreview: preview))
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
    }

    func update(for state: PipelineState) {
        hideTask?.cancel()
        switch state {
        case .idle:
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                self?.panel.orderOut(nil)
            }
        case .failed, .notice:
            show()
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                self?.panel.orderOut(nil)
            }
        default:
            show()
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
        guard let screen = targetScreen else {
            Self.log.error("no screen available for HUD")
            return
        }
        let size = RecordingHUDView.size(for: style, preview: preview)
        let frame = NSRect(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.minY + 18,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        Self.log.notice("HUD shown at \(NSStringFromRect(frame), privacy: .public) visible=\(self.panel.isVisible, privacy: .public)")
    }
}

/// Preview remains nonactivating and separate from the final transcript.
struct RecordingHUDView: View {
    var pipeline: DictationPipeline?
    var snapshot: HUDSnapshot?
    var style: HUDStyle
    var showPreview: Bool
    var sampleText: String?

    static func size(for style: HUDStyle, preview: Bool) -> CGSize {
        preview ? CGSize(width: 360, height: 120) : IndicatorView.size(for: style)
    }

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
        .frame(width: Self.size(for: style, preview: showPreview).width,
               height: Self.size(for: style, preview: showPreview).height, alignment: .bottom)
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

/// Dark pill, always the same in light and dark mode. Classic shows waveform
/// (3/5) plus elapsed time (2/5); Mini shows the waveform only.
struct IndicatorView: View {
    static func size(for style: HUDStyle) -> CGSize {
        switch style {
        case .classic: return CGSize(width: 172, height: 34)
        case .mini: return CGSize(width: 108, height: 30)
        case .none: return .zero
        }
    }

    var pipeline: DictationPipeline?
    var snapshot: HUDSnapshot?
    var style: HUDStyle = .classic

    init(pipeline: DictationPipeline, style: HUDStyle = .classic) { self.pipeline = pipeline; self.style = style }
    init(snapshot: HUDSnapshot, style: HUDStyle = .classic) { self.snapshot = snapshot; self.style = style }

    private var size: CGSize { Self.size(for: style) }

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
                    .padding(.horizontal, 14)
            } else if style == .mini {
                WaveformBars(levels: levels, dimmed: state != .recording)
                    .frame(width: size.width - 28, height: 14)
                    .background { HUDWaveformWell().padding(.horizontal, -5).padding(.vertical, -3) }
                    .padding(.horizontal, 14)
            } else {
                HStack(spacing: 10) {
                    WaveformBars(levels: levels, dimmed: state != .recording)
                        .frame(width: 72, height: 16)
                        .background { HUDWaveformWell().padding(.horizontal, -5).padding(.vertical, -3) }
                    ElapsedTime(pipeline: pipeline, snapshot: snapshot)
                        .frame(width: 62, alignment: .leading)
                }
                .padding(.horizontal, 14)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(
            RoundedRectangle(cornerRadius: size.height / 2, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.10)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: size.height / 2, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
        )
        .environment(\.colorScheme, .dark)
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
