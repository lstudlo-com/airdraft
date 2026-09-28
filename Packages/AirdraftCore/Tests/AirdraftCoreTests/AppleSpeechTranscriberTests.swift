import XCTest
@testable import AirdraftCore

final class AppleSpeechTranscriberTests: XCTestCase {
    func testCancelledRequestStopsBeforeLanguageAssetLookup() async {
        let engine = AppleSpeechTranscriber(locale: "und-cancellation-fixture")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await engine.transcribe(samples: [0.1], hints: .init())
        }
        do {
            _ = try await task.value
            XCTFail("A cancelled request must not start speech analysis")
        } catch is CancellationError {
            // Cancellation takes precedence over missing or unsupported assets.
        } catch {
            XCTFail("Expected cancellation, got \(error)")
        }
    }
}
