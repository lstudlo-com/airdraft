import SwiftUI

/// How to turn on the Airdraft keyboard and use it with a keyboard session.
struct KeyboardSetupView: View {
    var body: some View {
        SoftPage {
            SoftSection(title: "Turn on the keyboard") {
                Step(number: 1, text: "Open Airdraft in Settings, then Keyboards.")
                RowDivider()
                Step(number: 2, text: "Turn on Airdraft, then Allow Full Access.")
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.softProminent)
                Text("Full Access lets the keyboard receive your dictation from the Airdraft app. Airdraft never records what you type.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SoftSection(title: "Dictate in any app") {
                Step(number: 1, text: "Start a keyboard session in Airdraft, from Control Center or with the Action Button.")
                RowDivider()
                Step(number: 2, text: "In any app, switch to the Airdraft keyboard with the globe key.")
                RowDivider()
                Step(number: 3, text: "Tap the microphone, speak, then tap it again. Your text appears where you were typing.")
                Text("iOS does not let keyboards use the microphone, so the Airdraft app listens for the keyboard while a session is on. A Live Activity shows when it is.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("Keyboard")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct Step: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(number, format: .number)
                .font(.headline.monospacedDigit())
                .frame(width: 28, height: 28)
                .background { NeumorphicSurface(shape: Circle(), inset: true, depth: 1.5) }
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
