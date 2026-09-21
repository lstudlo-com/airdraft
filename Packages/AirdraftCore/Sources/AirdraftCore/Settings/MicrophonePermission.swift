import AVFoundation

/// Configuration and recording share one pending system request. Status checks
/// never request permission; only an explicit user action calls request().
@MainActor
public final class MicrophonePermission {
    public static let shared = MicrophonePermission()
    private let status: () -> AVAuthorizationStatus
    private let prompt: () async -> Bool
    private var pending: Task<Bool, Never>?

    public init(status: @escaping () -> AVAuthorizationStatus = { AVCaptureDevice.authorizationStatus(for: .audio) },
                prompt: @escaping () async -> Bool = { await AVCaptureDevice.requestAccess(for: .audio) }) {
        self.status = status
        self.prompt = prompt
    }

    public func request() async -> Bool {
        if let pending { return await pending.value }
        switch status() {
        case .authorized: return true
        case .notDetermined:
            let task = Task { await prompt() }
            pending = task
            let granted = await task.value
            pending = nil
            return granted
        default: return false
        }
    }
}
