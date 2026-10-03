#!/usr/bin/env python3
"""Verify the shared SwiftUI download indicator in a live, disposable window.

Compiles the production view and Progress value without starting the app or engines.
Captures only this fixture's own window; no Accessibility/Screen Recording grant needed.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)

with tempfile.TemporaryDirectory(prefix='airdraft-progress-ui-') as temporary:
    scratch = Path(temporary)
    downloader = (root / 'Packages/AirdraftCore/Sources/AirdraftCore/Providers/ModelDownloader.swift').read_text()
    start = downloader.index('    public struct Progress:')
    end = downloader.index('\n    public enum DownloadError:', start)
    (scratch / 'Progress.swift').write_text('import Foundation\nenum ModelDownloader {\n' + downloader[start:end] + '\n}\n')
    view = (root / 'Sources/App/Views/ModelDownloadProgress.swift').read_text().replace('import AirdraftCore\n', '')
    # SwiftUI's Reduce Motion environment is read-only. Inject that one input
    # into the fixture without changing the user's system accessibility settings.
    view = view.replace('@Environment(\\.accessibilityReduceMotion) private var reduceMotion', 'var reduceMotion: Bool')
    (scratch / 'View.swift').write_text(view)
    fixture = r'''
import AppKit
import SwiftUI

@MainActor private final class State: ObservableObject {
    @Published var progress = ModelDownloader.Progress(fraction: 0, currentFile: "Connecting…")
}

private struct Fixture: View {
    @ObservedObject var state: State
    let dark: Bool
    let reduceMotion: Bool
    var body: some View {
        ModelDownloadProgress(reduceMotion: reduceMotion, progress: state.progress)
            .frame(width: 440, alignment: .leading)
            .padding(20)
            .frame(width: 480, height: 90, alignment: .topLeading)
            .background(Color(white: dark ? 0.15 : 0.90))
            .tint(.blue)
            .environment(\.colorScheme, dark ? .dark : .light)
    }
}

@main enum Verify {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage") else {
            fatalError("Compositor capture unavailable")
        }
        let capture = unsafeBitCast(symbol, to: Capture.self)
        func settle(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

        for dark in [false, true] {
            for reduced in [false, true] {
                let state = State()
                let name = "\(dark ? "dark" : "light")-\(reduced ? "reduced" : "animated")"
                let window = NSWindow(contentRect: NSRect(x: 240, y: 240, width: 480, height: 90),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.contentView = NSHostingView(rootView: Fixture(state: state, dark: dark, reduceMotion: reduced))
                window.orderFrontRegardless()
                settle(0.3)
                func snapshot(_ label: String) throws -> Double {
                    guard let image = capture(.null, 1 << 3, UInt32(window.windowNumber), 1 << 0)?.takeRetainedValue() else {
                        fatalError("Own-window capture failed")
                    }
                    let bitmap = NSBitmapImageRep(cgImage: image)
                    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(name)-\(label).png"))
                    let scale = Double(image.width) / 480
                    // Count accent pixels across the track, away from rounded edges.
                    let y = Int(22 * scale)
                    let filled = (Int(20 * scale)..<Int(460 * scale)).filter { x in
                        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                        return color.blueComponent - color.redComponent > 0.25
                    }.count
                    return Double(filled) / (440 * scale)
                }
                func set(_ fraction: Double?, _ stage: String = "Downloading weights…") {
                    state.progress = .init(fraction: fraction, currentFile: stage)
                }
                let connecting = try snapshot("connecting")
                precondition(connecting < 0.01, "Connecting must be indeterminate")
                set(0.0000005)
                settle(0.25)
                _ = try snapshot("tiny")
                set(0.2)
                settle(0.3)
                let initial = try snapshot("start")
                precondition(abs(initial - 0.2) < 0.03, "Initial bar must reflect measured progress: \(initial)")
                set(0.8)
                var fractions: [Double] = []
                for frame in 0..<8 {
                    settle(0.03)
                    fractions.append(try snapshot("frame-\(frame)"))
                }
                if reduced {
                    precondition(fractions.allSatisfy { abs($0 - 0.8) < 0.03 }, "Reduce Motion must update directly: \(fractions)")
                } else {
                    precondition(fractions.contains { $0 > 0.24 && $0 < 0.76 }, "Must draw intermediate progress: \(fractions)")
                }
                precondition(zip(fractions, fractions.dropFirst()).allSatisfy { $1 >= $0 - 0.01 }, "Fill must advance monotonically")
                settle(0.5)
                let held = try snapshot("held")
                precondition(abs(held - 0.8) < 0.03, "Must not invent progress during a network pause")
                set(0.95)
                settle(0.03)
                set(nil, "Unpacking…")
                settle(0.3)
                let unpacking = try snapshot("unpacking")
                precondition(unpacking < 0.01, "Stage changes must stop the old fill")
                set(0, "Connecting…")
                settle(0.1)
                _ = try snapshot("retry")
                print("PASS \(name): \(fractions)")
                window.close()
            }
        }
    }
}
'''
    (scratch / 'Fixture.swift').write_text(fixture)
    binary = scratch / 'verify-progress'
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(scratch / 'Progress.swift'),
                    str(scratch / 'View.swift'), str(scratch / 'Fixture.swift'), '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(output)], check=True, timeout=40)
