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
    private let timerProvider: () -> HUDTimerOptions
    private let messagePasteboard: NSPasteboard
    private let reduceMotion: () -> Bool
    private var currentStyle: HUDStyle = .classic
    private var currentTimer = HUDTimerOptions()
    private var currentPreview = false
    private var lastVisibleState: PipelineState = .idle
    private var messageTimeoutTask: Task<Void, Never>?
    private var dismissalID: UUID?
    private var contentID = UUID()
    private var targetFrame: NSRect?
    private let spatialAnimation = SpatialHUDAnimation()

    init(pipeline: DictationPipeline, style: @escaping () -> HUDStyle,
         timer: @escaping () -> HUDTimerOptions = { HUDTimerOptions() },
         messagePasteboard: NSPasteboard = .general,
         reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) {
        self.pipeline = pipeline
        self.styleProvider = style
        self.timerProvider = timer
        self.messagePasteboard = messagePasteboard
        self.reduceMotion = reduceMotion
        panel = RecordingHUDPanel(
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
        _ = applyStyle(.classic, preview: false)
    }

    private func applyStyle(_ style: HUDStyle, preview: Bool) -> CGSize {
        currentStyle = style
        currentTimer = timerProvider()
        currentPreview = preview
        let id = UUID()
        contentID = id
        // Pipeline errors reset to idle before the HUD timeout. Keep the complete
        // message readable for its five seconds instead of restoring the waveform.
        let messageSnapshot = lastVisibleState.hudMessage == nil ? nil :
            HUDSnapshot(state: lastVisibleState, levels: [], elapsed: 0)
        let bounds = targetScreen?.visibleFrame.size ?? CGSize(width: 800, height: 600)
        let host = NSHostingView(rootView: RecordingHUDView(pipeline: messageSnapshot == nil ? pipeline : nil,
            snapshot: messageSnapshot, style: style, timer: currentTimer, showPreview: preview,
            messageMaxWidth: min(560, bounds.width - 36), messageMaxHeight: min(420, bounds.height - 60),
            messagePasteboard: messagePasteboard,
            spatialAnimation: spatialAnimation,
            onSizeChange: { [weak self] size in
                guard let self, self.contentID == id, self.dismissalID == nil else { return }
                self.resize(to: size, animated: messageSnapshot != nil)
            }))
        host.wantsLayer = true
        host.layer?.masksToBounds = true
        // The panel owns resizing. Hosting-view minimum-size constraints would
        // snap the window to its expanded size before AppKit can animate it.
        let size = host.fittingSize
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        return size
    }

    func update(for state: PipelineState, isStateChange: Bool = true) {
        switch state {
        case .idle:
            if messageTimeoutTask != nil, dismissalID == nil {
                if styleProvider() != currentStyle || timerProvider() != currentTimer { show() }
                return
            }
            dismiss()
        case .failed, .notice:
            // Successful delivery already started the exit. Recovery details
            // remain on Home; late notices must not reopen the capsule.
            if case .notice = state, dismissalID != nil { return }
            // Appearance changes must neither restart the deadline nor reopen
            // a message that has already timed out.
            if !isStateChange {
                if dismissalID == nil { show() }
                return
            }
            cancelDismissal()
            lastVisibleState = state
            show()
            messageTimeoutTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(5)) }
                catch { return }
                guard !Task.isCancelled else { return }
                self?.dismiss()
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
        messageTimeoutTask?.cancel()
        messageTimeoutTask = nil
        dismissalID = nil
        // Replaces an interrupted fade before showing a new recording.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
    }

    private func dismiss() {
        messageTimeoutTask?.cancel()
        messageTimeoutTask = nil
        guard dismissalID == nil else { return }
        let id = UUID()
        dismissalID = id
        guard panel.isVisible else { return }

        // The live pipeline can move to idle while the panel is fading. Freeze
        // the final display so idle cannot bring back the recording timer.
        let snapshot = HUDSnapshot(state: lastVisibleState, levels: pipeline.levelHistory,
                                   elapsed: pipeline.lastRecordingDuration,
                                   visualizerTime: spatialAnimation.motion.phase,
                                   visualizerEnergy: spatialAnimation.motion.energy)
        let host = NSHostingView(rootView: RecordingHUDView(snapshot: snapshot, style: currentStyle,
            timer: currentTimer, showPreview: currentPreview, sampleText: pipeline.previewIssue ?? pipeline.previewText))
        host.sizingOptions = []
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
            // Tear down animated content when the user hides the recording window.
            contentID = UUID()
            panel.contentView = nil
            return
        }
        let preview = pipeline.isRecording && pipeline.previewEnabledForRecording
        let message = lastVisibleState.hudMessage != nil
        let wasVisible = panel.isVisible
        let size = applyStyle(style, preview: preview)
        panel.ignoresMouseEvents = !message
        if message && !wasVisible {
            let compact = NSHostingView(rootView: IndicatorView(snapshot:
                HUDSnapshot(state: .recording, levels: [], elapsed: 0), style: style, timer: currentTimer)).fittingSize
            resize(to: compact)
        }
        panel.orderFrontRegardless()
        resize(to: size, animated: message)
        Self.log.notice("HUD shown at \(NSStringFromRect(self.panel.frame), privacy: .public) visible=\(self.panel.isVisible, privacy: .public)")
    }

    private func resize(to size: CGSize, animated: Bool = false) {
        guard size.width > 0, size.height > 0, let screen = targetScreen else { return }
        let frame = NSRect(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.minY + 18,
            width: size.width,
            height: size.height
        )
        guard targetFrame != frame else { return }
        targetFrame = frame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated && !reduceMotion() ? 0.28 : 0
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            panel.animator().setFrame(frame, display: true)
        }
    }
}

/// Copying a diagnostic must not move focus away from the dictation target.
private final class RecordingHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Preview remains nonactivating and separate from the final transcript.
struct RecordingHUDView: View {
    var pipeline: DictationPipeline?
    var snapshot: HUDSnapshot?
    var style: HUDStyle
    var timer = HUDTimerOptions()
    var showPreview: Bool
    var sampleText: String?
    var messageMaxWidth: CGFloat = 560
    var messageMaxHeight: CGFloat = 420
    var messagePasteboard: NSPasteboard = .general
    var spatialAnimation = SpatialHUDAnimation()
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
            IndicatorView(pipeline: pipeline, snapshot: snapshot, style: style, timer: timer,
                          messageMaxWidth: messageMaxWidth, messageMaxHeight: messageMaxHeight,
                          messagePasteboard: messagePasteboard, spatialAnimation: spatialAnimation)
        }
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSizeChange?($0) }
    }
}

extension PipelineState {
    var hudCaption: String? {
        switch self {
        case .preparingModel: return "Loading"
        case .transcribing: return "Transcribing"
        case .refining: return "Refining"
        case .inserting: return "Inserting"
        default: return nil
        }
    }

    /// Text the HUD shows instead of the waveform, if any.
    var hudMessage: String? {
        switch self {
        case .failed(let m), .notice(let m, _): return m
        default: return nil
        }
    }
}

/// Everything the HUD needs, decoupled from the pipeline so it can be rendered offscreen.
struct HUDSnapshot {
    var state: PipelineState
    var levels: [Float]
    var elapsed: TimeInterval
    /// Deterministic animation phase for previews; delivery snapshots stay still.
    var visualizerTime: TimeInterval = 1.4
    var visualizerEnergy: Double?
}

/// Preset artwork, optional timer and processing status share one content-sized pill.
struct IndicatorView: View {
    static let contentInset: CGFloat = 6

    var pipeline: DictationPipeline?
    var snapshot: HUDSnapshot?
    var style: HUDStyle = .classic
    var timer: HUDTimerOptions
    var messageMaxWidth: CGFloat = 560
    var messageMaxHeight: CGFloat = 420
    var messagePasteboard: NSPasteboard = .general
    var spatialAnimation: SpatialHUDAnimation

    init(pipeline: DictationPipeline? = nil, snapshot: HUDSnapshot? = nil, style: HUDStyle = .classic,
         timer: HUDTimerOptions = HUDTimerOptions(),
         messageMaxWidth: CGFloat = 560, messageMaxHeight: CGFloat = 420,
         messagePasteboard: NSPasteboard = .general,
         spatialAnimation: SpatialHUDAnimation = SpatialHUDAnimation()) {
        self.pipeline = pipeline
        self.snapshot = snapshot
        self.style = style
        self.timer = timer
        self.messageMaxWidth = messageMaxWidth
        self.messageMaxHeight = messageMaxHeight
        self.messagePasteboard = messagePasteboard
        self.spatialAnimation = spatialAnimation
    }

    private var state: PipelineState { snapshot?.state ?? pipeline?.state ?? .idle }
    private var levels: [Float] { snapshot?.levels ?? pipeline?.levelHistory ?? [] }

    var body: some View {
        Group {
            if let message = state.hudMessage {
                HUDMessageView(message: message, maxWidth: messageMaxWidth,
                               maxHeight: messageMaxHeight, pasteboard: messagePasteboard)
            } else {
                HStack(spacing: 8) {
                    if showsTimer && timer.position == .left {
                        ElapsedTime(pipeline: pipeline, snapshot: snapshot).fixedSize()
                            .accessibilityIdentifier("hud.timer")
                    }
                    visualizer
                        .accessibilityIdentifier("hud.visualizer")
                    if showsTimer && timer.position == .right {
                        ElapsedTime(pipeline: pipeline, snapshot: snapshot).fixedSize()
                            .accessibilityIdentifier("hud.timer")
                    }
                    if let caption = state.hudCaption {
                        Text(caption)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .fixedSize()
                            .accessibilityIdentifier("hud.status")
                    }
                }
            }
        }
        .padding(Self.contentInset)
        .fixedSize()
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.10)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
        )
        .environment(\.colorScheme, .dark)
    }

    private var showsTimer: Bool { timer.isEnabled && state == .recording }

    @ViewBuilder private var visualizer: some View {
        switch style {
        case .cube, .sonic:
            SpatialHUDVisualizer(style: style, levels: levels, recording: state == .recording,
                                 frozenTime: snapshot?.visualizerTime,
                                 frozenEnergy: snapshot?.visualizerEnergy, animation: spatialAnimation)
                .frame(width: 82, height: 22)
                .background { HUDWaveformWell() }
                .clipShape(Capsule())
        case .mini:
            waveform(width: 80, height: 14)
        case .classic, .none:
            waveform(width: 72, height: 16)
        }
    }

    private func waveform(width: CGFloat, height: CGFloat) -> some View {
        WaveformBars(levels: levels, dimmed: state != .recording)
            .frame(width: width, height: height)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background { HUDWaveformWell() }
    }
}

/// Full, wrapping diagnostics with a stationary copy action at the trailing edge.
struct HUDMessageView: View {
    let message: String
    var maxWidth: CGFloat = 560
    var maxHeight: CGFloat = 420
    var pasteboard: NSPasteboard = .general
    @State private var copied = false

    private var textSize: CGSize {
        let font = NSFont.systemFont(ofSize: 13)
        let natural = (message as NSString).size(withAttributes: [.font: font]).width
        let width = min(max(220, natural), max(1, maxWidth - 72))
        let bounds = (message as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
        return CGSize(width: ceil(width), height: ceil(bounds.height) + 2)
    }

    var body: some View {
        let size = textSize
        let height = min(size.height, max(1, maxHeight - 28))
        HStack(alignment: .top, spacing: 12) {
            Group {
                if size.height > height {
                    ScrollView(.vertical) { messageText }
                        .frame(height: height)
                } else {
                    messageText
                }
            }
            .frame(width: size.width, alignment: .leading)
            Button {
                copied = Self.copy(message, to: pasteboard)
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(copied ? "Copied" : "Copy Message")
            .accessibilityLabel(copied ? "Message Copied" : "Copy Message")
            .accessibilityIdentifier("hud.copyMessage")
        }
        .foregroundStyle(Color.white.opacity(0.95))
        .padding(8)
        .onChange(of: message) { copied = false }
    }

    private var messageText: some View {
        Text(verbatim: message)
            .font(.system(size: 13))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @discardableResult
    static func copy(_ message: String, to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(message, forType: .string)
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
            Text(format(seconds))
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.95))
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

}
