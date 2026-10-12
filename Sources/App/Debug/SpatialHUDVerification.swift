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
        verifyDiscoLogic()

        let input = Input()
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 660, height: 180),
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
        for style in [HUDStyle.cube, .sonic, .orbit, .silk] {
            input.style = style
            input.level = 0
            input.reduceMotion = false
            settle(0.3)
            let first = snapshot(style.rawValue + "-live-quiet")
            input.level = 0.65
            settle(0.4)
            let speaking = snapshot(style.rawValue + "-live-speaking")
            precondition(first != speaking, "\(style.title) must react to microphone-level changes")
            settle(0.25)
            precondition(snapshot(style.rawValue + "-live-motion") != speaking,
                         "\(style.title) live animation must advance")
            input.reduceMotion = true
            settle(0.2)
            let reduced = snapshot(style.rawValue + "-reduced-motion")
            settle(0.25)
            precondition(snapshot(style.rawValue + "-reduced-motion-held") == reduced,
                         "\(style.title) Reduce Motion must stop autonomous movement")
            input.level = 0
            settle(0.15)
            precondition(snapshot(style.rawValue + "-reduced-motion-silent") != reduced,
                         "\(style.title) Reduce Motion must still report input level")
        }
        print("PASS: compositor-rendered animation, speech response and static Reduce Motion")

        input.discoEnabled = true
        for style in HUDStyle.visibleStyles {
            input.style = style
            input.level = 0.65
            input.reduceMotion = false
            settle(0.4)
            let speaking = snapshot(style.rawValue + "-disco-speaking")
            precondition(chromaticPixels(in: speaking) > 12, "\(style.title) Disco must color its artwork")
            settle(0.35)
            precondition(snapshot(style.rawValue + "-disco-flow") != speaking,
                         "\(style.title) must keep color flowing with sustained speech")
            input.reduceMotion = true
            settle(0.2)
            let reduced = snapshot(style.rawValue + "-disco-reduced")
            settle(0.25)
            precondition(snapshot(style.rawValue + "-disco-reduced-held") == reduced,
                         "\(style.title) Disco must stop color travel with Reduce Motion")
            input.level = 0
            settle(0.2)
            let quiet = snapshot(style.rawValue + "-disco-reduced-quiet")
            precondition(chromaticPixels(in: quiet) < chromaticPixels(in: reduced),
                         "\(style.title) saturation must respond to input with Reduce Motion")
        }
        print("PASS: all five Disco artworks colorize, flow with speech and retain static Reduce Motion response")

        input.showsSettingsPreview = true
        for style in HUDStyle.visibleStyles {
            input.style = style
            input.reduceMotion = false
            settle(0.3)
            let first = snapshot(style.rawValue + "-settings-preview")
            settle(0.4)
            precondition(snapshot(style.rawValue + "-settings-preview-moving") != first,
                         "\(style.title) Settings specimen must animate")
            input.reduceMotion = true
            settle(0.3)
            let reduced = snapshot(style.rawValue + "-settings-preview-reduced")
            settle(0.3)
            precondition(snapshot(style.rawValue + "-settings-preview-reduced-held") == reduced,
                         "\(style.title) Settings specimen must respect Reduce Motion")
        }
        print("PASS: every production Settings specimen animates and pauses for Reduce Motion")

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

        var disco = HUDDiscoMotion()
        for frame in 0..<120 {
            let time = Double(frame) / 12
            for step in 0..<5 {
                let sampleTime = time + Double(step) / 60
                disco.advance(to: sampleTime, target: SpatialHUDMotion.energy(
                    levels: HUDPreview.samples(at: sampleTime), recording: true))
            }
            let renderer = ImageRenderer(content: DiscoPresentation(time: time, disco: disco.frame))
            renderer.scale = 2
            let bitmap = NSBitmapImageRep(data: renderer.nsImage!.tiffRepresentation!)!
            try! bitmap.representation(using: .png, properties: [:])!
                .write(to: directory.appendingPathComponent(String(format: "disco-frame-%03d.png", frame)))
        }
        print("PASS: 120 Disco comparison frames exported from the production palette integrator")
    }

    private static func verifyDiscoLogic() {
        var disco = HUDDiscoMotion()
        disco.advance(to: 0, target: 0)
        for step in 1...120 { disco.advance(to: Double(step) / 60, target: 0) }
        precondition(disco.frame.travel == 0 && disco.frame.energy == 0, "Silence must not cycle color")
        disco.advance(to: .nan, target: .infinity)
        for step in 121...240 { disco.advance(to: Double(step) / 60, target: 1) }
        precondition(disco.frame.energy > 0.99 && disco.frame.travel > 0.15)
        let speaking = disco.frame
        disco.advance(to: 241.0 / 60, target: 0)
        precondition(disco.frame.energy > 0.8, "Color release must soften pauses")
        for step in 242...600 { disco.advance(to: Double(step) / 60, target: 0) }
        precondition(disco.frame.energy < 0.001 && disco.frame.accent < 0.001)
        let settled = disco.frame.travel
        for step in 601...660 { disco.advance(to: Double(step) / 60, target: 0) }
        precondition(disco.frame.travel == settled, "Quiet color must hold after the release")
        for phase in stride(from: 0.0, to: 1.0, by: 0.025) {
            let frame = HUDDiscoFrame(travel: phase, energy: 1, accent: 0.4)
            let rgb = frame.components(at: 0.5)
            precondition([rgb.red, rgb.green, rgb.blue].allSatisfy { $0.isFinite && (0...1).contains($0) })
            func linear(_ value: Double) -> Double {
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            let luminance = 0.2126 * linear(rgb.red) + 0.7152 * linear(rgb.green) + 0.0722 * linear(rgb.blue)
            precondition((luminance + 0.05) / (linear(0.08) + 0.05) > 3,
                         "Disco's lit palette must remain visible in the dark well")
        }
        let seamA = HUDDiscoFrame(travel: 0.99999, energy: 0.8).components(at: 0)
        let seamB = HUDDiscoFrame(travel: 0.00001, energy: 0.8).components(at: 0)
        precondition(abs(seamA.red - seamB.red) + abs(seamA.green - seamB.green) + abs(seamA.blue - seamB.blue) < 0.001)
        precondition(speaking != .still(energy: 0), "Speech must change color independently of geometry")
        print("PASS: Disco silence gate, attack/release, bounded palette, contrast and continuous loop seam")
    }

    private static func chromaticPixels(in data: Data) -> Int {
        let bitmap = NSBitmapImageRep(data: data)!
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let channels = [color.redComponent, color.greenComponent, color.blueComponent]
                if channels.max()! - channels.min()! > 0.08 { count += 1 }
            }
        }
        return count
    }

    @Observable final class Input {
        var level: Float = 0
        var reduceMotion = false
        var style = HUDStyle.cube
        var showsSettingsPreview = false
        var discoEnabled = false
    }

    private struct Comparison: View {
        var input: Input
        var body: some View {
            HStack(spacing: 28) {
                Text(input.style.title).font(.system(size: 18, weight: .medium)).frame(width: 70)
                if input.showsSettingsPreview {
                    HUDPreview(style: input.style, discoEnabled: input.discoEnabled,
                               reduceMotionOverride: input.reduceMotion, renderModeOverride: false)
                        .environment(\.scenePhase, .active)
                        .frame(width: HUDPreview.size.width, height: HUDPreview.size.height)
                        .scaleEffect(2)
                        .frame(width: 340, height: 144)
                } else {
                    SpatialHUDVisualizer(style: input.style, levels: [input.level], recording: true,
                                         discoEnabled: input.discoEnabled,
                                         reduceMotionOverride: input.reduceMotion)
                        .frame(width: 82, height: 22)
                        .background(Color(white: 0.08), in: Capsule())
                        .scaleEffect(4)
                        .frame(width: 340, height: 90)
                }
            }
            .frame(width: 660, height: 180)
            .foregroundStyle(.white)
            .background(Color(white: 0.14))
        }
    }

    private struct DiscoPresentation: View {
        let time: Double
        let disco: HUDDiscoFrame
        var body: some View {
            VStack(spacing: 24) {
                HStack {
                    Text("Recording window").font(.system(size: 22, weight: .semibold))
                    Spacer()
                    Text("Disco").font(.system(size: 22, weight: .semibold))
                }
                HStack {
                    Text("Original").frame(maxWidth: .infinity)
                    Text("Disco").frame(maxWidth: .infinity)
                }
                .font(.system(size: 12)).foregroundStyle(.secondary)
                ForEach(HUDStyle.visibleStyles) { style in
                    VStack(spacing: 12) {
                        Text(style.title).font(.system(size: 14, weight: .medium))
                        HStack(spacing: 48) {
                            ForEach([false, true], id: \.self) { enabled in
                                IndicatorView(snapshot: HUDSnapshot(state: .recording,
                                    levels: HUDPreview.samples(at: time), elapsed: 7.4,
                                    visualizerTime: time * 1.8 + 0.65, visualizerDisco: disco),
                                    style: style, discoEnabled: enabled)
                                    .scaleEffect(2.7)
                                    .frame(maxWidth: .infinity).frame(height: 96)
                            }
                        }
                    }
                }
                Text("Simulated speech input · production recording artwork")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(32).frame(width: 700)
            .background(Color(white: 0.92)).environment(\.colorScheme, .light)
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
                ForEach(HUDStyle.visibleStyles) { style in
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(style.title).font(.system(size: 24, weight: .medium))
                            Spacer()
                            Text(description(for: style))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        IndicatorView(snapshot: HUDSnapshot(state: .recording,
                                                            levels: style == .classic ? HUDPreview.samples(at: time) : [level], elapsed: 7.4,
                                                            visualizerTime: time * 1.8 + 0.65), style: style)
                            .scaleEffect(3)
                            .frame(maxWidth: .infinity)
                            .frame(height: 104)
                    }
                }
                HStack {
                    Text("Enlarged 3× · simulated speech input")
                    Spacer()
                    Text("Classic / Cube / Sonic / Orbit / Silk")
                }
                .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(32)
            .frame(width: 620)
            .background(Color(white: 0.92))
            .environment(\.colorScheme, .light)
        }

        private func description(for style: HUDStyle) -> String {
            switch style {
            case .classic: return "Scrolling waveform"
            case .cube: return "Faceted silver · voice-reactive rotation"
            case .sonic: return "Braided sonic ribbons"
            case .orbit: return "Interlocking silver rings"
            case .silk: return "Folded metallic ribbon"
            case .none: return ""
            }
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
                ForEach(HUDStyle.visibleStyles) { style in
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
