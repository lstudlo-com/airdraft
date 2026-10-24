import Foundation

/// Anonymous outcome counts. Each call only hands an enumerated event to the
/// recorder, which returns at once; nothing here waits, throws or changes state.
extension DictationPipeline {
    /// Why recording did not start, or nil when it is not a failure to count
    /// (cancellation, a setup change asking for another press).
    nonisolated static func failureCategory(for error: Error) -> TelemetryEvent.FailureCategory? {
        if error is CancellationError { return nil }
        if let error = error as? RecordingPrerequisiteError {
            switch error.kind {
            case .permission: return .permission
            case .microphone: return .microphoneUnavailable
            case .modelMissing: return .modelMissing
            case .credential: return .credentialMissing
            case .setup: return .setupInvalid
            case .setupChanged: return nil
            }
        }
        if error is LicenseError { return .licenseRequired }
        if error is SpeechLanguageError { return .setupInvalid }
        return .other
    }

    func reportFailure(_ category: TelemetryEvent.FailureCategory?) {
        guard let category else { return }
        telemetry?.record(.dictationFailed(category))
    }

    /// One delivered (or attempted) dictation. Review-only work and onboarding
    /// practice are not counted.
    func reportCompletion(_ report: DeliveryReport, refinement: RefinementStage, snapshot: RecordingSnapshot,
                          seconds: Double, timings: DictationTimings) {
        guard let telemetry, !report.cancelledBeforeWriting else { return }
        let status: TextDeliveryStatus = report.inserted ? .delivered
            : report.sentUnverified ? .sentUnverified
            : report.outputSucceeded ? .delivered : .notDelivered
        let outcome: TelemetryEvent.RefinementOutcome = refinement.llmError != nil ? .fallback
            : refinement.llmEngine != nil ? .applied : .none
        let refinementProvider: LLMProviderKind = snapshot.profile.usesLLM ? snapshot.llm.kind : .none
        telemetry.record(.dictationCompleted(.init(
            engine: .init(snapshot.asr.kind), refinementProvider: refinementProvider,
            profile: .init(snapshot.profile), recordingDuration: .init(seconds: seconds),
            stopToDelivery: .init(milliseconds: timings.stopToDeliveryMs),
            deliveryStatus: status, refinementOutcome: outcome)))
        if report.deliveryError != nil, !report.outputSucceeded { telemetry.record(.dictationFailed(.deliveryFailed)) }
    }
}
