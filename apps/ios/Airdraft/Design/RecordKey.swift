import SwiftUI

/// Home's record key: one large raised key with the microphone in a recessed
/// socket. While recording it stays sunk into its well and shows Stop; while
/// processing it waits, dimmed, with a progress indicator.
struct RecordKey: View {
    enum Mode: Equatable {
        case idle
        case recording
        case busy
    }

    let mode: Mode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    NeumorphicSurface(shape: RoundedRectangle(cornerRadius: 16, style: .continuous),
                                      inset: true, depth: 2)
                    Group {
                        switch mode {
                        case .idle: Image(systemName: "mic.fill")
                        case .recording: Image(systemName: "stop.fill").foregroundStyle(Color.accentColor)
                        case .busy: ProgressView()
                        }
                    }
                    .font(.system(size: 28, weight: .semibold))
                }
                .frame(width: 64, height: 64)
                Text(label)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
        }
        .buttonStyle(RecordKeyStyle(sunk: mode == .recording))
        .disabled(mode == .busy)
        .accessibilityLabel(Text(label))
        .accessibilityHint(Text(hint))
    }

    private var label: LocalizedStringKey {
        switch mode {
        case .idle: "Record"
        case .recording: "Stop"
        case .busy: "Processing…"
        }
    }

    private var hint: LocalizedStringKey {
        switch mode {
        case .idle: "Starts recording your voice."
        case .recording: "Stops recording and turns your voice into text."
        case .busy: "Airdraft is turning your voice into text."
        }
    }
}

private struct RecordKeyStyle: ButtonStyle {
    let sunk: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                MobileRaisedSurface(shape: RoundedRectangle(cornerRadius: 28, style: .continuous),
                                    elevation: .hero, pressed: sunk || configuration.isPressed)
            }
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

/// The recessed well that shows recent input levels as raised gray bars, like
/// the Mac Home waveform. Decorative: the record key carries the state.
struct LevelWell: View {
    let levels: [Float]
    var barCount = 32

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let dark = scheme == .dark
        GeometryReader { geometry in
            let recent = Array(levels.suffix(barCount))
            let padded = Array(repeating: Float(0), count: max(0, barCount - recent.count)) + recent
            let spacing: CGFloat = 3
            let width = max(1, (geometry.size.width - 32 - spacing * CGFloat(barCount - 1)) / CGFloat(barCount))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(padded.enumerated()), id: \.offset) { _, level in
                    let height = max(4, CGFloat(min(1, level)) * (geometry.size.height - 20))
                    Capsule()
                        .fill(Color(white: dark ? 0.42 : 0.62))
                        .frame(width: width, height: height)
                        .background {
                            SurfaceShadows(shape: Capsule(), shadows: [
                                .init(color: .black.opacity(dark ? 0.6 : 0.25), radius: 1, x: 0.6, y: 0.9),
                                .init(color: .white.opacity(dark ? 0.08 : 0.9), radius: 1, x: -0.5, y: -0.6),
                            ])
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: levels.count)
        }
        .frame(height: 60)
        .background { NeumorphicSurface(shape: RoundedRectangle(cornerRadius: 14, style: .continuous), inset: true, depth: 2) }
        .accessibilityHidden(true)
    }
}
