import Observation

/// Runs `onChange` on the main actor after every change to the observable
/// values `read` touches. `withObservationTracking` fires once, so re-arm it.
@MainActor
func observeChanges(_ read: @escaping @MainActor () -> Void, onChange: @escaping @MainActor () -> Void) {
    withObservationTracking(read) {
        Task { @MainActor in
            onChange()
            observeChanges(read, onChange: onChange)
        }
    }
}
