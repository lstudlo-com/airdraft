import AirdraftCore
import SwiftUI

/// Every choice is saved as Airdraft's default, without changing other apps.
struct MicrophonePicker: View {
    @Environment(AppContainer.self) private var container
    var title = "Microphone"
    /// Device names come from hardware; the menu bar fits them to its width.
    var fitsMenu = false
    /// Pages show the raised soft picker at this width; the menu bar keeps the native menu.
    var width: CGFloat? = nil

    var body: some View {
        Group {
            if let width {
                SoftPicker(title, selection: selection, width: width) { choices }
            } else {
                Picker(title, selection: selection) { choices }
            }
        }
        .disabled(container.pipeline.state.isBusy)
        .onAppear { container.microphones.refresh() }
        .help("\(container.settings.microphone.name). Saved as Airdraft's default microphone. Finish dictation before switching.")
    }

    private var selection: Binding<String> {
        let store = container.microphones
        return Binding(
            get: { container.settings.microphone.uid ?? "" },
            set: { uid in
                let next: MicrophonePreference
                if let device = store.devices.first(where: { $0.uid == uid }) {
                    next = MicrophonePreference(uid: device.uid, name: device.name)
                } else if uid.isEmpty {
                    next = .systemDefault
                } else {
                    return
                }
                container.settings.microphone = store.selection(next, preservingChannelFrom: container.settings.microphone)
            }
        )
    }

    @ViewBuilder private var choices: some View {
        let store = container.microphones
        let preference = container.settings.microphone
        Text("System Default").tag("")
        ForEach(store.devices) { device in Text(label(device.name)).help(device.name).tag(device.uid) }
        if let uid = preference.uid, store.selected(preference) == nil {
            Text(label("\(preference.name) · unavailable")).help("\(preference.name) · unavailable").tag(uid)
        }
    }

    private func label(_ name: String) -> String { fitsMenu ? MenuTitle.fit(name) : name }
}

struct MicrophoneSettings: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        let store = container.microphones
        let preference = container.settings.microphone
        PageSection("Microphone") {
            SettingsCard {
                SettingRow(title: "Default microphone") {
                    MicrophonePicker(width: 230)
                }
                let channelCount = store.selected(preference)?.inputChannelCount ?? 0
                let selectedChannel = preference.channelIndex ?? 0
                if channelCount > 1 || selectedChannel != 0 {
                    RowDivider()
                    SettingRow(title: "Input channel", subtitle: "Your microphone’s physical input") {
                        SoftPicker("Input channel", selection: Binding(
                            get: { container.settings.microphone.channelIndex ?? 0 },
                            set: { container.settings.microphone.channelIndex = $0 }
                        ), width: 230) {
                            ForEach(0..<channelCount, id: \.self) { channel in
                                Text("Input \(channel + 1)").tag(channel)
                            }
                            if selectedChannel >= channelCount || selectedChannel < 0 {
                                Text("Input \(selectedChannel + 1) · unavailable").tag(selectedChannel)
                            }
                        }
                        .disabled(container.pipeline.isBusy)
                    }
                }
                if store.selected(preference) == nil {
                    RowDivider()
                    EmptyNote("Microphone unavailable. Connect it or choose another.")
                }
            }
        }
    }
}
