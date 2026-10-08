import AppKit
import AirdraftCore
import SwiftUI

struct MeetingSheet: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var selection = MeetingSourceSelection()
    @State private var includeMicrophone = true
    @State private var choosingApp = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionTitleSpacing) {
            Text("Record Meeting").font(.system(size: 18, weight: .semibold))
            SettingsCard {
                SettingRow(title: "App audio") {
                    Button { choosingApp = true } label: {
                        HStack { Text(selection.selectedName).lineLimit(1); Spacer(); Image(systemName: "chevron.down").font(.system(size: 10)) }.frame(width: 200)
                    }
                    .buttonStyle(SoftButtonStyle()).accessibilityLabel("Choose App Audio")
                    .accessibilityValue(selection.selectedName).accessibilityIdentifier("meeting.source")
                    .popover(isPresented: $choosingApp, arrowEdge: .bottom) {
                        MeetingSourceChoices(selection: selection) { choosingApp = false }
                    }
                }
                RowDivider()
                SettingRow(title: "Include microphone") {
                    Toggle("Include Microphone", isOn: $includeMicrophone).labelsHidden().toggleStyle(.softSwitch)
                }
            }
            if selection.unavailable {
                Text("\(selection.selectedName) is no longer available. Choose another app.").supportingText().foregroundStyle(.red)
            }
            Text("Let participants know you are recording. Audio is saved on this Mac.").supportingText()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(SoftButtonStyle())
                Button("Start Recording") {
                    container.navigation.page = .meetings
                    container.meeting?.start(applicationID: selection.selectedID, microphoneID: container.settings.microphone.uid,
                        microphone: includeMicrophone, microphoneChannel: container.settings.microphone.channelIndex ?? 0, sourceName: selection.selectedName)
                    dismiss()
                }.buttonStyle(SoftButtonStyle(prominent: true))
                    .disabled(container.pipeline.isBusy || container.meeting == nil || selection.unavailable)
                    .accessibilityIdentifier("meeting.start")
            }
        }.padding(Theme.pagePadding).frame(width: 480).background(Theme.islandBackground)
            .onAppear { if let meeting = container.meeting { selection.provider = meeting.sourceProvider } }
    }
}

private struct MeetingSourceChoices: View {
    let selection: MeetingSourceSelection
    let close: () -> Void

    private let rowHeight: CGFloat = 32
    private let rowSpacing: CGFloat = 4
    private var listHeight: CGFloat {
        let rows = min(selection.sources.count, 7)
        return CGFloat(rows) * rowHeight + CGFloat(max(0, rows - 1)) * rowSpacing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.controlSpacing) {
            HStack {
                Text("App audio").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Refresh") { Task { await selection.load() } }.buttonStyle(SoftButtonStyle()).disabled(selection.loading)
            }
            sourceButton("All Apps", id: nil) { selection.select(nil); close() }
            RowDivider()
            if selection.loading && selection.sources.isEmpty {
                ProgressView("Finding Apps…").controlSize(.small).frame(height: rowHeight)
            }
            if let issue = selection.issue {
                Text(issue).supportingText().textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Button("Open Recording Permissions") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }.buttonStyle(SoftButtonStyle())
            } else if selection.loaded && !selection.loading && selection.sources.isEmpty {
                Text("No apps available. Open an app and refresh, or choose All Apps.")
                    .supportingText().fixedSize(horizontal: false, vertical: true)
            }
            if !selection.sources.isEmpty {
                ScrollView {
                    VStack(spacing: rowSpacing) {
                        ForEach(selection.sources) { source in
                            sourceButton(source.name, id: source.id) { selection.select(source); close() }
                        }
                    }
                }
                // A height ceiling alone lets a popover collapse this viewport to zero.
                // Give it complete rows, then scroll when more apps are available.
                .frame(height: listHeight)
                .accessibilityIdentifier("meeting.sources.list")
            }
        }.padding(Theme.cardPadding).frame(width: 320).fixedSize(horizontal: false, vertical: true)
            .task { await selection.load() }
    }
    private func sourceButton(_ title: String, id: Int32?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title).lineLimit(1); Spacer(); if selection.selectedID == id { Image(systemName: "checkmark") } }
                .font(.system(size: 13)).frame(maxWidth: .infinity).frame(height: rowHeight).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title).help(title)
            .accessibilityIdentifier("meeting.source.\(id.map(String.init) ?? "all")")
    }
}

struct MeetingRecordingStatus: View {
    let meeting: MeetingController
    var body: some View {
        Card(spacing: Theme.controlSpacing) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.state == .starting ? "Starting…" : meeting.state == .finishing ? "Saving Recording…" : "Recording Meeting")
                        .font(.system(size: 13, weight: .medium))
                    Text(HistoryRecordingControls.time(meeting.elapsed)).font(.system(size: 23, weight: .medium)).monospacedDigit()
                }
                Spacer()
                if meeting.state == .starting { Button("Cancel") { meeting.cancelStart() }.buttonStyle(SoftButtonStyle()) }
                else if meeting.state == .recording {
                    Button("Stop and Save") { Task { await meeting.stop() } }.buttonStyle(SoftButtonStyle(prominent: true))
                        .accessibilityIdentifier("meeting.stop")
                } else { ProgressView().controlSize(.small) }
            }
            RowDivider()
            captureRow(meeting.sourceName, received: meeting.systemReceived, level: meeting.systemLevel)
            if meeting.microphoneEnabled {
                RowDivider()
                captureRow("Microphone", received: meeting.microphoneReceived, level: meeting.microphoneLevel)
            }
        }
    }
    private func captureRow(_ title: String, received: Bool, level: Float) -> some View {
        HStack {
            Text(title).font(.system(size: 13)); Spacer()
            Text(received ? "Receiving" : "Waiting for audio").supportingText()
            MicrophoneLevelMeter(level: level)
                .accessibilityHidden(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title) level, \(MicrophoneLevelMeter.steps(for: level)) of 10")
        }
    }
}
