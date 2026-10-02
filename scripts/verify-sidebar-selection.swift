// xcrun swiftc Sources/App/Views/NavigationStyle.swift Sources/App/Views/NeumorphicSurface.swift \
//   Sources/App/Views/SurfaceShadows.swift scripts/verify-sidebar-selection.swift -o /tmp/verify-sidebar-selection
// /tmp/verify-sidebar-selection [frames-dir]
// Captures this process's own window through the compositor (no Screen Recording access)
// while the selection changes, and checks that the sidebar well slides between rows,
// across a group gap, instead of switching on and off in place.
import AppKit
import SwiftUI

@MainActor private final class Selection: ObservableObject {
    @Published var row = 0
}

private struct SelectionFixture: View {
    static let size = CGSize(width: 220, height: 300)
    static let rowTops: [CGFloat] = [20, 60, 100, 154] // 38 pt rows, 2 pt spacing, then a 16 pt group gap
    @ObservedObject var selection: Selection

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(white: 0.6)
            VStack(alignment: .leading, spacing: 0) {
                group([0, 1, 2])
                group([3]).padding(.top, 16)
            }
            .sidebarSelectionWell(selection: selection.row)
            .frame(width: 180)
            .padding(.leading, 20)
            .padding(.top, 20)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .ignoresSafeArea()
    }

    private func group(_ rows: [Int]) -> some View {
        VStack(spacing: 2) {
            ForEach(rows, id: \.self) { row in
                Button {} label: {
                    HStack(spacing: 0) {
                        // Stands in for the row icon, so the icon island has an anchor to follow.
                        Color.clear.frame(width: NavigationStyle.iconIslandSize, height: 16).sidebarSelectionIconAnchor(row)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, NavigationStyle.iconIslandInset)
                    .frame(maxWidth: .infinity)
                    .frame(height: NavigationStyle.destinationHeight)
                }
                    .buttonStyle(NavigationRowStyle(selected: selection.row == row, slidingSelection: true))
                    .sidebarSelectionAnchor(row)
            }
        }
    }
}

@main
enum VerifySidebarSelection {
    @MainActor static func main() {
        _ = NSApplication.shared
        let output = CommandLine.arguments.dropFirst().first
        let selection = Selection()
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: 240, y: 240), size: SelectionFixture.size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: SelectionFixture(selection: selection))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))

        typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage") else {
            preconditionFailure("The compositor capture is unavailable")
        }
        let capture = unsafeBitCast(symbol, to: Capture.self)
        var frame = 0
        let iconX = 20 + NavigationStyle.iconIslandInset + NavigationStyle.iconIslandSize / 2
        /// Whether each capture shows the flat island face, lighter than its well, on row 3's icon.
        var islandOnTarget: [Bool] = []
        /// The vertical centre of the pixels that differ from the background along the row centre line.
        func wellCenter() -> CGFloat? {
            guard let image = capture(.null, 1 << 3, UInt32(window.windowNumber), 1 << 0)?.takeRetainedValue() else {
                preconditionFailure("The compositor capture is unavailable")
            }
            let bitmap = NSBitmapImageRep(cgImage: image)
            if let output {
                try? bitmap.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: output).appendingPathComponent(String(format: "frame-%02d.png", frame)))
            }
            frame += 1
            let scale = CGFloat(image.width) / SelectionFixture.size.width
            func shade(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
                bitmap.colorAt(x: Int(x * scale), y: Int(y * scale))!.usingColorSpace(.genericGray)!.whiteComponent
            }
            let targetY = SelectionFixture.rowTops[3] + NavigationStyle.destinationHeight / 2
            islandOnTarget.append(shade(iconX, targetY) - shade(150, targetY) > 0.03)
            let background = bitmap.colorAt(x: 4, y: 4)!.usingColorSpace(.genericGray)!.whiteComponent
            let rows = (0..<image.height).filter { y in
                let white = bitmap.colorAt(x: Int(110 * scale), y: y)!.usingColorSpace(.genericGray)!.whiteComponent
                return abs(white - background) > 0.015
            }
            guard let first = rows.first, let last = rows.last else { return nil }
            return CGFloat(first + last) / 2 / scale
        }
        func center(ofRow row: Int) -> CGFloat { SelectionFixture.rowTops[row] + NavigationStyle.destinationHeight / 2 }

        guard let start = wellCenter() else { preconditionFailure("No selection well was drawn") }
        precondition(abs(start - center(ofRow: 0)) < 2, "The well must start on the selected row (\(start))")

        selection.row = 3
        var samples: [CGFloat] = []
        for _ in 0..<16 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            if let y = wellCenter() { samples.append(y) }
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        guard let end = wellCenter() else { preconditionFailure("The well disappeared after the change") }
        print("Well centre: start \(start), samples \(samples.map { Int($0.rounded()) }), end \(end)")

        let travel = center(ofRow: 3) - center(ofRow: 0)
        precondition(abs(end - center(ofRow: 3)) < 2, "The well must settle on the new row (\(end))")
        let between = samples.filter { $0 > start + travel * 0.1 && $0 < end - travel * 0.1 }
        precondition(between.count >= 2, "The well must pass through intermediate positions, not toggle")
        precondition(zip(samples, samples.dropFirst()).allSatisfy { $1 >= $0 - 0.5 }, "The well must move in one direction")
        // Ease-in-out S-curve: gentle first and last steps around a faster middle.
        let path = [start] + samples
        let steps = zip(path, path.dropFirst()).map { $1 - $0 }
        guard let firstMove = steps.firstIndex(where: { $0 > 0.5 }), let fastest = steps.max() else {
            preconditionFailure("The well never moved")
        }
        precondition(steps[firstMove] < fastest * 0.75, "The motion must ease in (steps \(steps.map { Int($0.rounded()) }))")
        precondition(steps.count > 9 && between.count >= 4, "The motion must last long enough to read as a glide")
        // The island follows 300 ms behind the well: absent when the well settles, present at the end.
        guard let settled = samples.firstIndex(where: { abs($0 - center(ofRow: 3)) < 1 }) else {
            preconditionFailure("The well never settled")
        }
        precondition(!islandOnTarget[settled + 1], "The icon island must arrive after its well, not with it")
        precondition(islandOnTarget.last == true, "The icon island must follow the well to the new row")
        // The icon island settles on the new row's icon.
        guard let image = capture(.null, 1 << 3, UInt32(window.windowNumber), 1 << 0)?.takeRetainedValue() else {
            preconditionFailure("The compositor capture is unavailable")
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        let scale = CGFloat(image.width) / SelectionFixture.size.width
        func white(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
            bitmap.colorAt(x: Int(x * scale), y: Int(y * scale))!.usingColorSpace(.genericGray)!.whiteComponent
        }
        // The flat island face is lighter than the well around it and leaves the old row.
        precondition(white(iconX, center(ofRow: 3)) - white(150, center(ofRow: 3)) > 0.03,
                     "A raised island must rest in the well under the selected icon")
        precondition(abs(white(iconX, center(ofRow: 0)) - white(150, center(ofRow: 0))) < 0.02,
                     "The island must leave the previously selected row")
        // Its shade stays inside the well: just outside the well's bottom edge is plain background.
        precondition(abs(white(iconX, SelectionFixture.rowTops[3] + NavigationStyle.destinationHeight + 0.5) - white(4, 4)) < 0.02,
                     "The island's shade must not leak outside the well")
        print("PASS: The selection well slides across rows and the group gap, then settles on the new row")
    }
}
