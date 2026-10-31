import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct AirdraftWidgets: WidgetBundle {
    var body: some Widget {
        DictationLiveActivity()
        DictateControl()
        KeyboardSessionControl()
    }
}

/// Control Center, Lock Screen and Action Button control: record now.
struct DictateControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.lstudlo.app.airdraft.control.dictate") {
            ControlWidgetButton(action: StartDictationIntent()) {
                Label(String(localized: "Dictate", table: "Shared"), systemImage: "mic.fill")
            }
        }
        .displayName(LocalizedStringResource("Dictate", table: "Shared"))
        .description(LocalizedStringResource("Opens Airdraft and starts recording.", table: "Shared"))
    }
}

/// Opens a keyboard session so the Airdraft keyboard can record from any app.
struct KeyboardSessionControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.lstudlo.app.airdraft.control.session") {
            ControlWidgetButton(action: StartKeyboardSessionIntent()) {
                Label(String(localized: "Keyboard Session", table: "Shared"), systemImage: "keyboard")
            }
        }
        .displayName(LocalizedStringResource("Keyboard Session", table: "Shared"))
        .description(LocalizedStringResource("Keeps Airdraft listening for the Airdraft keyboard for a while.", table: "Shared"))
    }
}

struct DictationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DictationActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .padding(16)
                .activityBackgroundTint(Color(white: 0.12))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: activitySymbol(for: context.state.phase))
                        .font(.title2)
                        .foregroundStyle(activityTint(for: context.state.phase))
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(activityTitle(for: context.state.phase))
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimeLabel(state: context.state)
                        .font(.headline.monospacedDigit())
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(activityDetail(for: context.state))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: activitySymbol(for: context.state.phase))
                    .foregroundStyle(activityTint(for: context.state.phase))
            } compactTrailing: {
                TimeLabel(state: context.state)
                    .monospacedDigit()
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: activitySymbol(for: context.state.phase))
                    .foregroundStyle(activityTint(for: context.state.phase))
            }
        }
    }
}

private struct LockScreenView: View {
    let state: DictationActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: activitySymbol(for: state.phase))
                .font(.title)
                .foregroundStyle(activityTint(for: state.phase))
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(activityTitle(for: state.phase))
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(activityDetail(for: state))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 8)
            TimeLabel(state: state)
                .font(.title3.monospacedDigit())
                .foregroundStyle(.white)
        }
    }
}

/// Recording time while recording; otherwise when the session ends.
private struct TimeLabel: View {
    let state: DictationActivityAttributes.ContentState

    var body: some View {
        if state.phase == .recording, let started = state.recordingStartedAt {
            Text(started, style: .timer)
        } else if let ends = state.endsAt {
            Text(timerInterval: Date.now...max(ends, .now), countsDown: true)
        }
    }
}

private func activitySymbol(for phase: DictationActivityAttributes.ContentState.Phase) -> String {
    switch phase {
    case .ready: "mic"
    case .recording: "mic.fill"
    case .processing: "waveform"
    }
}

private func activityTint(for phase: DictationActivityAttributes.ContentState.Phase) -> Color {
    phase == .recording ? .accentColor : .white
}

private func activityTitle(for phase: DictationActivityAttributes.ContentState.Phase) -> String {
    switch phase {
    case .ready: String(localized: "Airdraft is ready")
    case .recording: String(localized: "Listening")
    case .processing: String(localized: "Writing your text")
    }
}

private func activityDetail(for state: DictationActivityAttributes.ContentState) -> String {
    switch state.phase {
    case .ready: String(localized: "Tap the microphone on the Airdraft keyboard.")
    case .recording: String(localized: "Tap the microphone again to finish.")
    case .processing: String(localized: "Your text appears where you were typing.")
    }
}
