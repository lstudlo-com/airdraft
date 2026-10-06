#if DEBUG
import AppKit
import AirdraftCore
import Observation
import SwiftUI

/// Production views in a disposable window. No microphone, model or credentials.
@MainActor
enum SpatialHUDVerification {
    static func run(to directory: URL) {
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        precondition(SpatialHUDMotion.energy(levels: [], recording: true) == 0)
        precondition(SpatialHUDMotion.energy(levels: [0, .nan, .infinity], recording: true) == 0)
        precondition(SpatialHUDMotion.energy(levels: [1, 1], recording: false) == 0)
        var motion = SpatialHUDMotion()
        motion.advance(to: 0, target: 0, recording: true)
        for step in 1...60 { motion.advance(to: Double(step) / 60, target: 1, recording: true) }
        precondition(motion.energy > 0.99)
        let speakingPhase = motion.phase
        for step in 61...120 { motion.advance(to: Double(step) / 60, target: 0, recording: true) }
        precondition(motion.energy < 0.01 && motion.phase > speakingPhase)
        print("PASS: bounded input, silent/processing energy, attack/release and continuous rotation")

        let input = Input()
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 660, height: 350),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.contentView = NSHostingView(rootView: Comparison(input: input))
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage") else {
            preconditionFailure("Own-window compositor capture unavailable")
        }
        let capture = unsafeBitCast(symbol, to: Capture.self)
        func settle(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        func snapshot(_ name: String) -> Data {
            guard let image = capture(.null, 1 << 3, UInt32(window.windowNumber), 1 << 0)?.takeRetainedValue(),
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                preconditionFailure("Own-window capture failed")
            }
            try! png.write(to: directory.appendingPathComponent(name + ".png"))
            return png
        }
        settle(0.3)
        let first = snapshot("live-quiet")
        input.level = 0.65
        settle(0.4)
        let speaking = snapshot("live-speaking")
        precondition(first != speaking, "Microphone-level changes must change the artwork")
        settle(0.25)
        precondition(snapshot("live-rotation") != speaking, "Live animation must advance between frames")
        input.reduceMotion = true
        settle(0.2)
        let reduced = snapshot("reduced-motion")
        settle(0.25)
        precondition(snapshot("reduced-motion-held") == reduced, "Reduce Motion must stop autonomous movement")
        input.level = 0
        settle(0.15)
        precondition(snapshot("reduced-motion-silent") != reduced, "Reduce Motion must still report input level")
        print("PASS: compositor-rendered animation, speech response and static Reduce Motion")

        let timerRenderer = ImageRenderer(content: TimerComparison())
        timerRenderer.scale = 2
        let timerImage = timerRenderer.nsImage!
        let timerBitmap = NSBitmapImageRep(data: timerImage.tiffRepresentation!)!
        try! timerBitmap.representation(using: .png, properties: [:])!
            .write(to: directory.appendingPathComponent("timer-options.png"))

        input.reduceMotion = false
        for frame in 0..<72 {
            let time = Double(frame) / 24
            let level = Float(0.04 + 0.62 * pow(0.5 + 0.5 * sin(time * 3), 2))
            let content = Presentation(time: time, level: level)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                preconditionFailure("HUD presentation render failed")
            }
            try! png.write(to: directory.appendingPathComponent(String(format: "frame-%03d.png", frame)))
        }
        print("PASS: 72 deterministic production-HUD frames exported")
    }

    @Observable final class Input {
        var level: Float = 0
        var reduceMotion = false
    }

    private struct Comparison: View {
        var input: Input
        var body: some View {
            VStack(spacing: 35) {
                ForEach([HUDStyle.cube, .sonic]) { style in
                    HStack(spacing: 28) {
                        Text(style.title).font(.system(size: 18, weight: .medium)).frame(width: 70)
                        SpatialHUDVisualizer(style: style, levels: [input.level], recording: true,
                                             reduceMotionOverride: input.reduceMotion)
                            .frame(width: 82, height: 22)
                            .background(Color(white: 0.08), in: Capsule())
                            .scaleEffect(4)
                            .frame(width: 340, height: 90)
                    }
                }
            }
            .frame(width: 660, height: 350)
            .foregroundStyle(.white)
            .background(Color(white: 0.14))
        }
    }

    private struct Presentation: View {
        let time: Double
        let level: Float
        var body: some View {
            VStack(alignment: .leading, spacing: 32) {
                HStack {
                    Text("AIRDRAFT").font(.system(size: 11, weight: .semibold)).tracking(2.5)
                    Spacer()
                    Text("Recording capsules").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                ForEach([HUDStyle.cube, .sonic]) { style in
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(style.title).font(.system(size: 24, weight: .medium))
                            Spacer()
                            Text(style == .cube ? "Faceted silver · voice-reactive rotation" : "Sonic ribbons · spatial interference")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        IndicatorView(snapshot: HUDSnapshot(state: .recording, levels: [level], elapsed: 7.4,
                                                            visualizerTime: time * 1.8 + 0.65), style: style)
                            .scaleEffect(3)
                            .frame(maxWidth: .infinity)
                            .frame(height: 104)
                    }
                }
                HStack {
                    Text("Enlarged 3× · simulated speech input")
                    Spacer()
                    Text("Cube / Sonic")
                }
                .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(32)
            .frame(width: 620)
            .background(Color(white: 0.92))
            .environment(\.colorScheme, .light)
        }
    }

    private struct TimerComparison: View {
        private let options = [HUDTimerOptions(), HUDTimerOptions(isEnabled: true, position: .left),
                               HUDTimerOptions(isEnabled: true, position: .right)]
        var body: some View {
            VStack(alignment: .leading, spacing: 28) {
                Text("Recording window").font(.system(size: 24, weight: .medium))
                HStack {
                    Text("PRESET").frame(width: 70, alignment: .leading)
                    ForEach(["Timer off · default", "Timer left", "Timer right"], id: \.self) { title in
                        Text(title).frame(width: 180)
                    }
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
                ForEach([HUDStyle.classic, .mini, .cube, .sonic]) { style in
                    HStack {
                        Text(style.title).font(.system(size: 13, weight: .medium)).frame(width: 70, alignment: .leading)
                        ForEach(options.indices, id: \.self) { index in
                            IndicatorView(snapshot: HUDSnapshot(state: .recording,
                                levels: [0.1, 0.3, 0.6, 0.25, 0.4, 0.1, 0.7, 0.3], elapsed: 7.4),
                                style: style, timer: options[index])
                                .frame(width: 180)
                        }
                    }
                }
                Text("One timer setting for every preset. Sonic shows only the animated ribbons.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(32)
            .background(Color(white: 0.92))
            .environment(\.colorScheme, .light)
        }
    }
}
#endif
