import SwiftUI

/// One large microphone key over a row of space, delete and return. The keys
/// use the app's raised material; the globe key appears when iOS asks for it.
struct KeyboardView: View {
    let model: KeyboardModel
    let showsGlobe: Bool

    var body: some View {
        VStack(spacing: 10) {
            status
                .frame(maxWidth: .infinity, minHeight: 20)
            Button { model.microphoneTapped() } label: {
                HStack(spacing: 10) {
                    microphoneSymbol
                        .font(.system(size: 22, weight: .semibold))
                    Text(microphoneLabel)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 64)
            }
            .buttonStyle(KeyStyle(sunk: isRecording, radius: 16))
            .disabled(model.mode == .processing)
            .accessibilityLabel(Text(microphoneLabel))
            HStack(spacing: 8) {
                if showsGlobe {
                    Button { model.nextKeyboard() } label: {
                        Image(systemName: "globe").frame(width: 44, height: 44)
                    }
                    .buttonStyle(KeyStyle())
                    .accessibilityLabel(Text("Next Keyboard"))
                }
                Button { model.insertSpace() } label: {
                    Text("space").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(KeyStyle())
                .accessibilityLabel(Text("Space"))
                RepeatingKey(action: model.deleteBackward) {
                    Image(systemName: "delete.backward").frame(width: 56, height: 44)
                }
                .accessibilityLabel(Text("Delete"))
                Button { model.insertReturn() } label: {
                    Image(systemName: "return").frame(width: 56, height: 44)
                }
                .buttonStyle(KeyStyle())
                .accessibilityLabel(Text("Return"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .foregroundStyle(.primary)
    }

    private var isRecording: Bool {
        if case .recording = model.mode { return true }
        return false
    }

    @ViewBuilder private var microphoneSymbol: some View {
        switch model.mode {
        case .recording: Image(systemName: "stop.fill").foregroundStyle(Color.accentColor)
        case .processing: ProgressView()
        default: Image(systemName: "mic.fill")
        }
    }

    private var microphoneLabel: LocalizedStringKey {
        switch model.mode {
        case .recording: "Tap to Finish"
        case .processing: "Writing…"
        case .ready: "Tap to Dictate"
        case .needsSession, .needsFullAccess: "Dictate"
        }
    }

    @ViewBuilder private var status: some View {
        Group {
            switch model.mode {
            case .needsFullAccess:
                Text("Allow Full Access for Airdraft in Settings to dictate.")
            case .needsSession:
                Text(model.message ?? String(localized: "Start a keyboard session in the Airdraft app to dictate."))
            case .recording(let since):
                if let since {
                    HStack(spacing: 6) {
                        Text("Listening")
                        Text(since, style: .timer).monospacedDigit()
                    }
                } else {
                    Text("Listening")
                }
            case .processing:
                Text("Turning your voice into text…")
            case .ready:
                Text(model.message ?? String(localized: "Ready"))
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .lineLimit(2)
    }
}

/// A raised key that sinks while pressed, or stays sunk while it is active.
private struct KeyStyle: ButtonStyle {
    var sunk = false
    var radius: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        KeyFace(pressed: sunk || configuration.isPressed, radius: radius) { configuration.label }
    }
}

private struct KeyFace<Label: View>: View {
    let pressed: Bool
    let radius: CGFloat
    @ViewBuilder var label: Label
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        label
            .background {
                if pressed {
                    shape.fill(Color(white: dark ? 0.15 : 0.84)
                        .shadow(.inner(color: .black.opacity(dark ? 0.6 : 0.25), radius: 3, x: 1.5, y: 2))
                        .shadow(.inner(color: .white.opacity(dark ? 0.08 : 0.9), radius: 3, x: -1.5, y: -2)))
                } else {
                    shape.fill(Color(white: dark ? 0.27 : 0.97))
                        .background {
                            SurfaceShadows(shape: shape, shadows: [
                                .init(color: .black.opacity(dark ? 0.55 : 0.22), radius: 2.5, x: 1.5, y: 2),
                                .init(color: .white.opacity(dark ? 0.06 : 0.9), radius: 2.5, x: -1, y: -1.5),
                            ])
                        }
                }
            }
            .contentShape(shape)
    }
}

/// Delete repeats while held, like the system keyboard.
private struct RepeatingKey<Label: View>: View {
    let action: () -> Void
    @ViewBuilder var label: Label
    @State private var pressing = false
    @State private var repeater: Task<Void, Never>?

    var body: some View {
        KeyFace(pressed: pressing, radius: 10) { label }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressing else { return }
                    pressing = true
                    action()
                    repeater = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(450))
                        while !Task.isCancelled {
                            action()
                            try? await Task.sleep(for: .milliseconds(90))
                        }
                    }
                }
                .onEnded { _ in
                    pressing = false
                    repeater?.cancel()
                })
    }
}
