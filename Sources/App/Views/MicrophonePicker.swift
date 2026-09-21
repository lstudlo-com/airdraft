import AirdraftCore
import SwiftUI

/// Every choice is saved as Airdraft's default, without changing other apps.
struct MicrophonePicker: View {
    @Environment(AppContainer.self) private var container
    var title = "Microphone"

    var body: some View {
        let store = container.microphones
        let preference = container.settings.microphone
        Picker(title, selection: Binding(
            get: { container.settings.microphone.uid ?? "" },
            set: { uid in
                if let device = store.devices.first(where: { $0.uid == uid }) {
                    container.settings.microphone = MicrophonePreference(uid: device.uid, name: device.name)
                } else if uid.isEmpty {
                    container.settings.microphone = .systemDefault
                }
            }
        )) {
            Text("System default").tag("")
            ForEach(store.devices) { device in Text(device.name).tag(device.uid) }
            if let uid = preference.uid, store.selected(preference) == nil {
                Text("\(preference.name) · unavailable").tag(uid)
            }
        }
        .disabled(container.pipeline.state.isBusy)
        .onAppear { store.refresh() }
        .help("Saved as Airdraft's default microphone. Finish dictation before switching.")
    }
}

struct MicrophoneSettings: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        let store = container.microphones
        let preference = container.settings.microphone
        PageSection("Microphone") {
            SettingsCard {
                SettingRow(title: "Default microphone", subtitle: "Saved for every recording and next launch") {
                    MicrophonePicker().labelsHidden().frame(width: 230)
                }
                RowDivider()
                HStack(spacing: 8) {
                    Image(systemName: store.selected(preference) == nil ? "mic.slash" : "mic")
                    Text(store.label(preference))
                    Spacer()
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                Text(preference.uid == nil
                     ? "Follows the input selected in macOS Sound settings."
                     : "Uses this device even when macOS changes its default. If disconnected, reconnect it or select another microphone.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
