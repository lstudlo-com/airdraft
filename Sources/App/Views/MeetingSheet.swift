import AppKit
import AirdraftCore
import SwiftUI

struct MeetingSheet: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var sources: [MeetingAudioSource] = []
    @State private var applicationID: Int32 = 0
    @State private var includeMicrophone = true
    @State private var loading = false
    @State private var sourceIssue: String?
    @State private var showTranscription = false
    private var meeting: MeetingController? { container.meeting }
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionTitleSpacing) {
            HStack {
                Text(meeting?.isBusy == true ? "Recording Meeting" : "Record Meeting").font(.system(size: 18, weight: .semibold))
                Spacer()
                Button("Close") { dismiss() }.buttonStyle(SoftButtonStyle()).keyboardShortcut(.cancelAction)
            }
            if let meeting, meeting.isBusy {
                SettingsCard {
                    HStack {
                        Text(meeting.state == .starting ? "Starting…" : meeting.state == .finishing ? "Saving Recording…" : HistoryRecordingControls.time(meeting.elapsed))
                            .font(.system(size: 23, weight: .medium, design: .monospaced))
                        Spacer()
                        if meeting.state == .starting { Button("Cancel") { meeting.cancelStart() }.buttonStyle(SoftButtonStyle()) }
                        else if meeting.state == .recording {
                            Button("Stop and Save") { Task { await meeting.stop() } }.buttonStyle(.borderedProminent)
                        } else { ProgressView().controlSize(.small) }
                    }
                    RowDivider()
                    if meeting.microphoneEnabled { captureRow("Microphone", received: meeting.microphoneReceived, level: meeting.microphoneLevel) }
                    else { HStack { Text("Microphone").font(.system(size: 13)); Spacer(); Text("Off").supportingText() } }
                    RowDivider()
                    captureRow(meeting.sourceName, received: meeting.systemReceived, level: meeting.systemLevel)
                }
                Text("You can close this window. Stop recording from the menu bar or History.").supportingText()
            } else {
                SettingsCard {
                    HStack {
                        Text("App audio").font(.system(size: 13)); Spacer()
                        SoftPicker("App audio", selection: $applicationID, width: 200) {
                            Text("All Apps").tag(Int32(0))
                            ForEach(sources) { source in Text(source.name).tag(source.id) }
                        }
                    }
                    HStack {
                        Text("Choose an app to limit capture. Browsers include all their audio.").supportingText()
                        Spacer()
                        Button(loading ? "Loading…" : "Choose App…") { loadSources() }.buttonStyle(SoftButtonStyle()).disabled(loading)
                    }
                    RowDivider()
                    HStack { Text("Include microphone").font(.system(size: 13)); Spacer(); Toggle("Include Microphone", isOn: $includeMicrophone).toggleStyle(.softSwitch) }
                    if includeMicrophone { Text("Uses the microphone selected in the sidebar. Headphones reduce echo.").supportingText() }
                }
                HStack(alignment: .top) {
                    Text("macOS asks for Screen & System Audio Recording permission. Only audio is saved. Make sure participants know you are recording.").supportingText().fixedSize(horizontal: false, vertical: true)
                    Button("Permissions") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!) }.buttonStyle(SoftButtonStyle())
                }
                Text("Up to two hours. Microphone and app audio are kept on separate WAV channels until you delete them. Transcribe after saving.").supportingText().fixedSize(horizontal: false, vertical: true)
                HStack {
                    if let saved = meeting?.saved {
                        Text("Recording saved to History.").supportingText()
                        Spacer()
                        Button("Transcribe…") { showTranscription = true }.buttonStyle(SoftButtonStyle())
                            .disabled(container.pipeline.isBusy)
                            .help("Transcribe the saved \(Int(saved.duration))-second recording")
                    } else { Spacer() }
                    Button("Start Recording") {
                        meeting?.start(applicationID: applicationID == 0 ? nil : applicationID,
                            microphoneID: container.settings.microphone.uid, microphone: includeMicrophone, microphoneChannel: container.settings.microphone.channelIndex ?? 0, sourceName: sources.first(where: { $0.id == applicationID })?.name ?? "All Apps")
                    }.buttonStyle(.borderedProminent).disabled(container.pipeline.isBusy || meeting == nil || loading)
                }
            }
            if let issue = sourceIssue ?? meeting?.issue ?? meeting?.recoveryIssue {
                HStack(alignment: .top) {
                    Text(issue).supportingText().textSelection(.enabled)
                    Spacer()
                    if sourceIssue != nil || meeting?.issue != nil {
                        Button("Dismiss") { sourceIssue = nil; meeting?.issue = nil }.buttonStyle(SoftButtonStyle())
                    } else { Button("Retry") { meeting?.refreshDrafts() }.buttonStyle(SoftButtonStyle()) }
                }
            }
            if let meeting, !meeting.drafts.isEmpty, !meeting.isBusy {
                RowDivider()
                HStack {
                    Text("\(meeting.drafts.count) interrupted recording(s) can be recovered.").supportingText()
                    Spacer()
                    Menu("Recover") {
                        ForEach(meeting.drafts) { draft in
                            Button(draft.createdAt.formatted(date: .abbreviated, time: .standard)) { meeting.recover(draft) }
                        }
                    }.menuStyle(.borderlessButton).fixedSize().disabled(container.pipeline.isBusy)
                }
            }
        }.padding(Theme.pagePadding).frame(width: 480).background(Theme.islandBackground)
            .sheet(isPresented: $showTranscription) { MediaImportSheet(source: nil, recording: meeting?.saved).environment(container) }
    }
    private func captureRow(_ title: String, received: Bool, level: Float) -> some View {
        HStack {
            Text(title).font(.system(size: 13)); Spacer()
            Text(received ? "Receiving" : "Waiting for audio").supportingText()
            ProgressView(value: min(1, Double(level) * 4)).frame(width: 80).accessibilityLabel(title + " level")
        }
    }
    private func loadSources() {
        loading = true; sourceIssue = nil
        Task {
            defer { loading = false }
            do { sources = try await MeetingCaptureSession.sources() }
            catch { sourceIssue = error.localizedDescription }
        }
    }
}
