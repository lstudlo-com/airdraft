import Foundation
import XCTest
@testable import Airdraft

/// The keyboard and the app agree on shared state through `KeyboardBridge`;
/// these cover what each side relies on, with a disposable defaults suite.
final class KeyboardBridgeTests: XCTestCase {
    func testStoreRoundTripsStateRequestDeliveryAndReceipt() throws {
        let suite = "airdraft.bridge.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = try XCTUnwrap(KeyboardBridge.Store(defaults: defaults))

        do { // EmptyStoreReadsAsOff
            XCTAssertEqual(store.state, .off)
            XCTAssertNil(store.request)
            XCTAssertNil(store.delivery)
            XCTAssertNil(store.receipt)
        }

        do { // ValuesRoundTrip
            let now = Date(timeIntervalSince1970: 1_000)
            let state = KeyboardBridge.State(phase: .ready, endsAt: now.addingTimeInterval(300),
                                             recordingStartedAt: nil, message: nil, updatedAt: now)
            store.state = state
            XCTAssertEqual(store.state, state)
            let request = KeyboardBridge.Request(id: UUID(), createdAt: now)
            store.request = request
            XCTAssertEqual(store.request, request)
            let delivery = KeyboardBridge.Delivery(id: UUID(), requestID: request.id, text: "Hello", createdAt: now)
            store.delivery = delivery
            XCTAssertEqual(store.delivery, delivery)
            store.receipt = KeyboardBridge.Receipt(id: delivery.id, confirmed: true)
            XCTAssertEqual(store.receipt?.confirmed, true)
        }

        do { // ClearingRemovesTheText
            store.delivery = nil
            XCTAssertNil(store.delivery)
            XCTAssertNil(defaults.data(forKey: "bridge.delivery"))
        }
    }

    func testSessionLivenessAndDeliveryLifetime() {
        let now = Date(timeIntervalSince1970: 10_000)
        let ready = KeyboardBridge.State(phase: .ready, endsAt: now.addingTimeInterval(60),
                                         recordingStartedAt: nil, message: nil, updatedAt: now)
        XCTAssertTrue(ready.isLive(at: now))
        XCTAssertFalse(ready.isLive(at: now.addingTimeInterval(61)), "an ended session is not live")
        var missingEnd = ready
        missingEnd.endsAt = nil
        XCTAssertFalse(missingEnd.isLive(at: now), "a state without a session end is from a closed app")
        XCTAssertFalse(KeyboardBridge.State.off.isLive(at: now))

        let delivery = KeyboardBridge.Delivery(id: UUID(), requestID: UUID(), text: "x", createdAt: now)
        XCTAssertTrue(delivery.isFresh(at: now.addingTimeInterval(59)))
        XCTAssertFalse(delivery.isFresh(at: now.addingTimeInterval(60)), "text never lingers in shared storage")
    }

    func testInsertionIsConfirmedByTheFieldBeforeTheCursor() {
        XCTAssertTrue(KeyboardBridge.confirms("Hello there.", contextBeforeInput: "Note: Hello there."))
        XCTAssertFalse(KeyboardBridge.confirms("Hello there.", contextBeforeInput: "Note: "))
        XCTAssertFalse(KeyboardBridge.confirms("Hello", contextBeforeInput: nil))
        XCTAssertFalse(KeyboardBridge.confirms("", contextBeforeInput: "anything"))
        let long = String(repeating: "word ", count: 40) + "end."
        XCTAssertTrue(KeyboardBridge.confirms(long, contextBeforeInput: String(long.suffix(60))),
                      "a long insertion is confirmed by its visible tail")
    }
}
