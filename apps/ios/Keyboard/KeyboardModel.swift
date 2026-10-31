import Foundation
import Observation
import UIKit

/// The keyboard's side of `KeyboardBridge`: shows the app's session state,
/// asks it to start or stop, and inserts the text it delivers for this
/// keyboard's own request.
@MainActor
@Observable
final class KeyboardModel {
    enum Mode: Equatable {
        /// Without Full Access the keyboard cannot reach the app.
        case needsFullAccess
        /// No running session: start one in Airdraft.
        case needsSession
        case ready
        case recording(since: Date?)
        case processing
    }

    private(set) var mode: Mode = .needsSession
    private(set) var message: String?

    @ObservationIgnored private let proxy: () -> UITextDocumentProxy?
    @ObservationIgnored private let hasFullAccess: () -> Bool
    @ObservationIgnored let nextKeyboard: () -> Void
    @ObservationIgnored private let listener = DarwinSignalListener()
    @ObservationIgnored private var store: KeyboardBridge.Store?
    /// This keyboard process's pending request; only its delivery is inserted.
    @ObservationIgnored private var request: KeyboardBridge.Request?
    @ObservationIgnored private var inserted: Set<UUID> = []
    @ObservationIgnored private var startTimeout: Task<Void, Never>?

    init(proxy: @escaping () -> UITextDocumentProxy?, hasFullAccess: @escaping () -> Bool,
         nextKeyboard: @escaping () -> Void) {
        self.proxy = proxy
        self.hasFullAccess = hasFullAccess
        self.nextKeyboard = nextKeyboard
        listener.observe(.state) { [weak self] in self?.refresh() }
    }

    func refresh() {
        guard hasFullAccess() else {
            mode = .needsFullAccess
            return
        }
        if store == nil { store = KeyboardBridge.Store() }
        guard let store else {
            mode = .needsFullAccess
            return
        }
        let state = store.state
        let now = Date()
        message = state.message
        if state.isLive(at: now) {
            switch state.phase {
            case .ready: mode = .ready
            case .recording: mode = .recording(since: state.recordingStartedAt)
            case .processing: mode = .processing
            case .off: mode = .needsSession
            }
            if state.phase != .ready { startTimeout?.cancel() }
        } else {
            mode = .needsSession
        }
        insertDeliveryIfOurs(store)
    }

    func microphoneTapped() {
        guard let store else { refresh(); return }
        switch mode {
        case .ready:
            let request = KeyboardBridge.Request(id: UUID(), createdAt: Date())
            self.request = request
            store.request = request
            KeyboardBridge.post(.start)
            UIDevice.current.playInputClick()
            // The app answers within a moment while its session runs; if it
            // does not, its process has ended and the session with it.
            startTimeout?.cancel()
            startTimeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled, let self, self.mode == .ready else { return }
                self.message = String(localized: "Airdraft didn't answer. Start a keyboard session in Airdraft again.")
                self.mode = .needsSession
            }
        case .recording:
            KeyboardBridge.post(.stop)
            UIDevice.current.playInputClick()
        case .processing, .needsSession, .needsFullAccess:
            refresh()
        }
    }

    /// Leaving the field cancels a recording made for it.
    func leave() {
        guard request != nil else { return }
        if case .recording = mode { KeyboardBridge.post(.cancel) }
        request = nil
    }

    private func insertDeliveryIfOurs(_ store: KeyboardBridge.Store) {
        guard let delivery = store.delivery, let request, delivery.requestID == request.id,
              !inserted.contains(delivery.id), delivery.isFresh(at: Date()), let proxy = proxy() else { return }
        inserted.insert(delivery.id)
        self.request = nil
        proxy.insertText(delivery.text)
        let confirmed = KeyboardBridge.confirms(delivery.text, contextBeforeInput: proxy.documentContextBeforeInput)
        store.receipt = KeyboardBridge.Receipt(id: delivery.id, confirmed: confirmed)
        KeyboardBridge.post(.consumed)
    }

    // MARK: - Keys

    func insertSpace() {
        proxy()?.insertText(" ")
        UIDevice.current.playInputClick()
    }

    func insertReturn() {
        proxy()?.insertText("\n")
        UIDevice.current.playInputClick()
    }

    func deleteBackward() {
        proxy()?.deleteBackward()
        UIDevice.current.playInputClick()
    }
}
