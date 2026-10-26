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
    private let discoProvider: () -> Bool
    private let timerProvider: () -> HUDTimerOptions
    private let messagePasteboard: NSPasteboard
    private let reduceMotion: () -> Bool
    private let screenFrame: () -> NSRect?
    private var currentStyle: HUDStyle = .classic
    private var currentDisco = false
    private var currentTimer = HUDTimerOptions()
    private var currentPreview = false
    private var lastVisibleState: PipelineState = .idle
    private var messageTimeoutTask: Task<Void, Never>?
    private var dismissalID: UUID?
    private var contentID = UUID()
    private var targetFrame: NSRect?
    private let spatialAnimation = SpatialHUDAnimation()
    private let previewNotice = HUDPreviewNotice()

    init(pipeline: DictationPipeline, style: @escaping () -> HUDStyle,
         disco: @escaping () -> Bool = { false },
         timer: @escaping () -> HUDTimerOptions = { HUDTimerOptions() },
         messagePasteboard: NSPasteboard = .general,
         reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
         screenFrame: (() -> NSRect?)? = nil) {
        self.pipeline = pipeline
        self.styleProvider = style
        self.discoProvider = disco
        self.timerProvider = timer
        self.messagePasteboard = messagePasteboard
        self.reduceMotion = reduceMotion
        self.screenFrame = screenFrame ?? {
            let mouse = NSEvent.mouseLocation
            return (NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
        }
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
        currentDisco = discoProvider()
        currentTimer = timerProvider()
        currentPreview = preview
        let id = UUID()
        contentID = id
        // Pipeline errors reset to idle before the HUD timeout. Keep the complete
        // message readable for its five seconds instead of restoring the waveform.
        let messageSnapshot = lastVisibleState.hudMessage == nil ? nil :
            HUDSnapshot(state: lastVisibleState, levels: [], elapsed: 0)
        let bounds = screenFrame()?.size ?? CGSize(width: 800, height: 600)
        let host = NSHostingView(rootView: RecordingHUDView(pipeline: messageSnapshot == nil ? pipeline : nil,
            snapshot: messageSnapshot, style: style, timer: currentTimer, discoEnabled: currentDisco, showPreview: preview,
            messageMaxWidth: min(560, bounds.width - 36), messageMaxHeight: min(420, bounds.height - 60),
            messagePasteboard: messagePasteboard,
            spatialAnimation: spatialAnimation,
            previewNotice: previewNotice,
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
                if styleProvider() != currentStyle || discoProvider() != currentDisco || timerProvider() != currentTimer { show() }
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
        let reduced = reduceMotion()
        let staticEnergy = SpatialHUDMotion.energy(levels: pipeline.levelHistory, recording: lastVisibleState == .recording)
        let snapshot = HUDSnapshot(state: lastVisibleState, levels: pipeline.levelHistory,
                                   elapsed: pipeline.lastRecordingDuration,
                                   visualizerTime: spatialAnimation.motion.phase,
                                   visualizerEnergy: reduced ? staticEnergy : spatialAnimation.motion.energy,
                                   visualizerDisco: reduced ? .still(energy: staticEnergy) : spatialAnimation.disco.frame)
        let bounds = screenFrame()?.size ?? CGSize(width: 800, height: 600)
        let host = NSHostingView(rootView: RecordingHUDView(snapshot: snapshot, style: currentStyle,
            timer: currentTimer, discoEnabled: currentDisco, showPreview: currentPreview,
            sampleText: currentPreview ? pipeline.previewIssue ?? pipeline.previewText : nil,
            messageMaxWidth: min(560, bounds.width - 36), messageMaxHeight: min(420, bounds.height - 60),
            messagePasteboard: messagePasteboard))
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
        previewNotice.present(HUDPreviewNotice.message(for: pipeline))
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
        guard size.width > 0, size.height > 0, let screen = screenFrame() else { return }
        let frame = NSRect(
            x: screen.midX - size.width / 2,
            y: screen.minY + 18,
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
    var discoEnabled = false
    var showPreview: Bool
    var sampleText: String?
    var messageMaxWidth: CGFloat = 560
    var messageMaxHeight: CGFloat = 420
    var messagePasteboard: NSPasteboard = .general
    var spatialAnimation = SpatialHUDAnimation()
    var previewNotice: HUDPreviewNotice?
    var onSizeChange: ((CGSize) -> Void)?

    private var liveText: String? {
        let text = sampleText ?? pipeline?.previewIssue ?? pipeline?.previewText
        return text?.isEmpty == false ? text : nil
    }

    var body: some View {
        VStack(spacing: 8) {
            if let notice = previewNotice?.message {
                LivePreviewNotice(message: notice)
                    .opacity(previewNotice?.isFading == true ? 0 : 1)
            } else if showPreview {
                LivePreviewCard(text: liveText)
            }
            IndicatorView(pipeline: pipeline, snapshot: snapshot, style: style, timer: timer,
                          discoEnabled: discoEnabled,
                          messageMaxWidth: messageMaxWidth, messageMaxHeight: messageMaxHeight,
                          messagePasteboard: messagePasteboard, spatialAnimation: spatialAnimation)
        }
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSizeChange?($0) }
        // Follows the pipeline between HUD rebuilds; presenting is idempotent.
        .onChange(of: pipeline.flatMap(HUDPreviewNotice.message(for:)), initial: true) { _, message in
            if pipeline != nil { previewNotice?.present(message) }
        }
    }
}

/// Live text floats above the capsule on dark glass. The newest words stay
/// crisp at the bottom; earlier lines scroll up and dissolve into the material.
struct LivePreviewCard: View {
    static let width: CGFloat = 280
    static let fontSize: CGFloat = 12.5
    /// Two full lines plus the fading tail of a third.
    nonisolated static let textHeight: CGFloat = 42
    static let cornerRadius: CGFloat = 14

    var text: String?
    @State private var overflows = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shown = text ?? String(localized: "Listening…")
        Text(shown)
            .font(.system(size: Self.fontSize, weight: .medium))
            .lineSpacing(1.5)
            .foregroundStyle(Color.white.opacity(text == nil ? 0.45 : 0.92))
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
            .lineLimit(5)
            .truncationMode(.head)
            .naturalAlignment(for: shown)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: Bool.self) { $0.size.height > Self.textHeight + 0.5 } action: { overflows = $0 }
            // Short text keeps the card one line tall; longer text fills it and
            // its oldest line fades out under the top edge.
            .frame(maxHeight: Self.textHeight, alignment: .bottom)
            .clipped()
            .mask {
                if overflows {
                    LinearGradient(stops: [.init(color: .clear, location: 0.06),
                                           .init(color: .black.opacity(0.4), location: 0.24),
                                           .init(color: .black, location: 0.46)],
                                   startPoint: .top, endPoint: .bottom)
                } else {
                    Color.black
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: shown)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(width: Self.width)
            .background { HUDGlass(shape: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)) }
            .environment(\.colorScheme, .dark)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("hud.liveText")
    }
}

/// A model without live text says so briefly; the live-text window stays closed.
struct LivePreviewNotice: View {
    static let maxWidth: CGFloat = 280
    var message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "text.bubble")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.6))
                .accessibilityHidden(true)
            Text(message)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.88))
                .lineLimit(2)
                .naturalAlignment(for: message)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: Self.maxWidth, alignment: .leading)
        .fixedSize()
        .background { HUDGlass(shape: RoundedRectangle(cornerRadius: 12, style: .continuous)) }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("hud.liveTextNotice")
    }
}

/// Translucent smoked glass: the desktop shows through, blurred, under a dark
/// tint that keeps white text legible over light documents. Reduce
/// Transparency makes it opaque.
struct HUDGlass<S: InsettableShape>: View {
    var shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if reduceTransparency {
                shape.fill(Color(white: 0.12))
            } else {
                shape.fill(.ultraThinMaterial)
                shape.fill(LinearGradient(colors: [Color.black.opacity(0.42), Color.black.opacity(0.56)],
                                          startPoint: .top, endPoint: .bottom))
            }
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.05)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
                .physicalLight()
        }
        .environment(\.colorScheme, .dark)
    }
}

/// Shows why a recording has no live text for two seconds, then fades it.
/// The controller owns it so rebuilding the HUD's content never restarts it.
@MainActor @Observable
final class HUDPreviewNotice {
    private(set) var message: String?
    private(set) var isFading = false
    @ObservationIgnored private var presented: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let visibleFor: TimeInterval
    @ObservationIgnored private let fadeFor: TimeInterval
    /// Waits out a phase; tests pass a manual clock so they never race real time.
    typealias Sleep = @MainActor (TimeInterval) async throws -> Void
    @ObservationIgnored private let sleep: Sleep

    init(visibleFor: TimeInterval = 2, fadeFor: TimeInterval = 0.3,
         sleep: @escaping Sleep = { try await Task.sleep(for: .seconds($0)) }) {
        self.visibleFor = visibleFor
        self.fadeFor = fadeFor
        self.sleep = sleep
    }

    /// The notice for a recording whose live-text window stays closed.
    static func message(for pipeline: DictationPipeline) -> String? {
        pipeline.isRecording && !pipeline.previewEnabledForRecording ? pipeline.previewIssue : nil
    }

    /// Presenting the same message again keeps its original deadline; a new
    /// recording clears it first, so its notice shows again.
    func present(_ next: String?) {
        guard next != presented else { return }
        presented = next
        task?.cancel()
        isFading = false
        message = next
        guard next != nil else { return }
        task = Task { [weak self, visibleFor, fadeFor, sleep] in
            do { try await sleep(visibleFor) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: fadeFor)) { self?.isFading = true }
            do { try await sleep(fadeFor) } catch { return }
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }
}

extension PipelineState {
    var hudCaption: String? {
        switch self {
        case .preparingModel: return String(localized: "Loading", comment: "Recording window status")
        case .transcribing: return String(localized: "Transcribing", comment: "Recording window status")
        case .refining: return String(localized: "Refining", comment: "Recording window status")
        case .inserting: return String(localized: "Inserting", comment: "Recording window status")
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

    var hudAllowsCopy: Bool {
        if case .failed = self { return true }
        return false
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
    var visualizerDisco: HUDDiscoFrame?
    /// The recording's send lock or Edit target (AD-104).
    var badge: String?
}

/// Preset artwork, optional timer and processing status share one content-sized pill.
struct IndicatorView: View {
    static let contentInset: CGFloat = 6
    static let textOuterInset: CGFloat = 12
    static let visualizerSize = CGSize(width: 82, height: 22)

    var pipeline: DictationPipeline?
    var snapshot: HUDSnapshot?
    var style: HUDStyle = .classic
    var timer: HUDTimerOptions
    var discoEnabled: Bool
    var messageMaxWidth: CGFloat = 560
    var messageMaxHeight: CGFloat = 420
    var messagePasteboard: NSPasteboard = .general
    var spatialAnimation: SpatialHUDAnimation

    init(pipeline: DictationPipeline? = nil, snapshot: HUDSnapshot? = nil, style: HUDStyle = .classic,
         timer: HUDTimerOptions = HUDTimerOptions(),
         discoEnabled: Bool = false,
         messageMaxWidth: CGFloat = 560, messageMaxHeight: CGFloat = 420,
         messagePasteboard: NSPasteboard = .general,
         spatialAnimation: SpatialHUDAnimation = SpatialHUDAnimation()) {
        self.pipeline = pipeline
        self.snapshot = snapshot
        self.style = style
        self.timer = timer
        self.discoEnabled = discoEnabled
        self.messageMaxWidth = messageMaxWidth
        self.messageMaxHeight = messageMaxHeight
        self.messagePasteboard = messagePasteboard
        self.spatialAnimation = spatialAnimation
    }

    @Environment(\.layoutDirection) private var layoutDirection

    private var state: PipelineState { snapshot?.state ?? pipeline?.state ?? .idle }
    private var levels: [Float] { snapshot?.levels ?? pipeline?.levelHistory ?? [] }

    var body: some View {
        Group {
            if let message = state.hudMessage {
                HUDMessageView(message: message, allowsCopy: state.hudAllowsCopy, maxWidth: messageMaxWidth,
                               maxHeight: messageMaxHeight, pasteboard: messagePasteboard)
            } else {
                HStack(spacing: 8) {
                    if showsTimer && timer.position == .left {
                        ElapsedTime(pipeline: pipeline, snapshot: snapshot).fixedSize()
                            .padding(.leading, Self.textOuterInset - Self.contentInset)
                            .accessibilityIdentifier("hud.timer")
                    }
                    visualizer
                        .accessibilityIdentifier("hud.visualizer")
                    if showsTimer && timer.position == .right {
                        ElapsedTime(pipeline: pipeline, snapshot: snapshot).fixedSize()
                            .padding(.trailing, Self.textOuterInset - Self.contentInset)
                            .accessibilityIdentifier("hud.timer")
                    }
                    if let caption {
                        Text(caption)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .fixedSize()
                            .environment(\.layoutDirection, layoutDirection)
                            .padding(.trailing, Self.textOuterInset - Self.contentInset)
                            .accessibilityIdentifier("hud.status")
                    }
                }
                // The capsule is an instrument: the waveform runs left to right, Timer
                // position names a physical side, and the status follows the waveform,
                // in every language.
                .environment(\.layoutDirection, .leftToRight)
            }
        }
        .padding(Self.contentInset)
        .fixedSize()
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.10)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .physicalLight()
        )
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
                .physicalLight()
        )
        .environment(\.colorScheme, .dark)
    }

    private var showsTimer: Bool { timer.isEnabled && state == .recording }

    /// Processing status, or while recording the send lock or Edit target (AD-104).
    private var caption: String? {
        if state == .recording {
            if let badge = snapshot?.badge { return badge }
            guard let pipeline else { return nil }
            if pipeline.sendLocked { return String(localized: "Send ↩", comment: "Recording window: Return will be pressed after pasting") }
            return pipeline.recordingBadge
        }
        if state == .inserting, pipeline?.isSendPending == true {
            return String(localized: "Sending", comment: "Recording window status")
        }
        return state.hudCaption
    }

    private var visualizer: some View {
        SpatialHUDVisualizer(style: style, levels: levels, recording: state == .recording,
                             discoEnabled: discoEnabled,
                             frozenTime: snapshot?.visualizerTime,
                             frozenEnergy: snapshot?.visualizerEnergy,
                             frozenDisco: snapshot?.visualizerDisco, animation: spatialAnimation)
        .frame(width: Self.visualizerSize.width, height: Self.visualizerSize.height)
        .background { HUDWaveformWell() }
        .clipShape(Capsule())
    }
}

/// Full, wrapping messages. Only errors offer a copy action, keeping delivered text safe.
struct HUDMessageView: View {
    let message: String
    let allowsCopy: Bool
    var maxWidth: CGFloat = 560
    var maxHeight: CGFloat = 420
    var pasteboard: NSPasteboard = .general
    @State private var copied = false

    private var textSize: CGSize {
        let font = NSFont.systemFont(ofSize: 13)
        let natural = (message as NSString).size(withAttributes: [.font: font]).width
        let width = min(max(allowsCopy ? 220 : 1, natural), max(1, maxWidth - 28 - (allowsCopy ? 40 : 0)))
        let bounds = (message as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
        return CGSize(width: ceil(width), height: ceil(bounds.height) + 2)
    }

    var body: some View {
        let size = textSize
        let height = min(size.height, max(1, maxHeight - 28))
        HStack(alignment: .center, spacing: 12) {
            Group {
                if size.height > height {
                    ScrollView(.vertical) { messageText }
                        .frame(height: height)
                } else {
                    messageText
                }
            }
            .frame(width: size.width, alignment: .leading)
            if allowsCopy {
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
            // Provider diagnostics often stay English in a right-to-left interface.
            .naturalAlignment(for: message)
            .accessibilityIdentifier("hud.message")
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
    var disco: HUDDiscoFrame?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let count = DictationPipeline.levelHistoryLength
    /// Quiet input still fills the pill: bars are drawn relative to the loudest
    /// of the visible samples. The floor keeps silence flat instead of amplifying
    /// room noise into a full-height waveform.
    private static let quietFloor: Float = 0.2

    var body: some View {
        GeometryReader { geo in
            let padded = Array(repeating: Float(0), count: max(0, count - levels.count)) + levels.suffix(count)
            let peak = max(Self.quietFloor, padded.max() ?? 0)
            let spacing: CGFloat = 1.5
            let barWidth = max(1.5, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(padded.enumerated()), id: \.offset) { index, level in
                    Capsule(style: .continuous)
                        .fill((disco?.color(at: Double(index) / Double(count - 1),
                                            shade: 0.72 + Double(shaped(level / peak)) * 0.28) ?? .white)
                            .opacity(dimmed ? 0.28 : 0.92))
                        .frame(width: barWidth, height: max(2.5, CGFloat(shaped(level / peak)) * geo.size.height))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(reduceMotion ? nil : .linear(duration: 0.08), value: padded)
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
