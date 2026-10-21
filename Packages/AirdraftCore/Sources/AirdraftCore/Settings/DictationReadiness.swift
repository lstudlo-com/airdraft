import Foundation

/// A condition outside setup that the pipeline enforces before new dictation.
/// Home's readiness lists these beside the setup rows, so it never reports Ready
/// while the shortcut would open the License sheet or refuse to record.
public enum DictationBlocker: Equatable, Sendable {
    /// An official build without a trial or license that allows new work.
    case license(LicenseStore.Access)
    /// The kept failed recordings fill their count or duration bound.
    case waitingRecordings

    /// Blockers in the order Home lists them. A license read still in flight is
    /// not one: the pipeline's access check joins it instead of refusing.
    public static func current(license: LicenseStore.Access, canKeepAnotherRecording: Bool) -> [DictationBlocker] {
        var blockers: [DictationBlocker] = []
        if !license.allowsUse && license != .loading { blockers.append(.license(license)) }
        if !canKeepAnotherRecording { blockers.append(.waitingRecordings) }
        return blockers
    }
}

/// What Home's hero shows above its waveform. The first-dictation headline needs
/// History to have loaded and be empty; an unreadable or missing History is
/// never presented as a new user's first run.
public enum HomeHistoryContent: Equatable, Sendable {
    case loading, metrics, firstDictation, unavailable

    public init(loaded: Bool, available: Bool, hasDictations: Bool) {
        if !available { self = .unavailable }
        else if !loaded { self = .loading }
        else { self = hasDictations ? .metrics : .firstDictation }
    }
}
