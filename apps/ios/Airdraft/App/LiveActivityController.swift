import ActivityKit
import Foundation

/// Keeps one Live Activity in step with the keyboard session and recording,
/// so the open microphone is always visible outside the app.
@MainActor
final class LiveActivityController {
    /// Activities are not Sendable; keep only the identifier and look the
    /// activity up inside each update's own task.
    private var activityID: String?
    private var shown: DictationActivityAttributes.ContentState?

    init() {
        // A previous process cannot have an input open any more.
        Task.detached {
            for activity in Activity<DictationActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    func show(_ state: KeyboardBridge.State) {
        let content: DictationActivityAttributes.ContentState? = switch state.phase {
        case .off: nil
        case .ready: .init(phase: .ready, endsAt: state.endsAt, recordingStartedAt: nil)
        case .recording: .init(phase: .recording, endsAt: state.endsAt, recordingStartedAt: state.recordingStartedAt)
        case .processing: .init(phase: .processing, endsAt: state.endsAt, recordingStartedAt: nil)
        }
        guard content != shown else { return }
        shown = content
        guard let content else {
            if let id = activityID { Self.end(id) }
            activityID = nil
            return
        }
        if let id = activityID {
            Task.detached {
                for activity in Activity<DictationActivityAttributes>.activities where activity.id == id {
                    await activity.update(ActivityContent(state: content, staleDate: content.endsAt))
                }
            }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            activityID = try? Activity.request(attributes: DictationActivityAttributes(),
                                               content: ActivityContent(state: content, staleDate: content.endsAt)).id
        }
    }

    private static func end(_ id: String) {
        Task.detached {
            for activity in Activity<DictationActivityAttributes>.activities where activity.id == id {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
