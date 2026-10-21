import Synchronization

/// Mutable fixture state shared by a test and URLProtocol, recorder or delegate
/// threads. Values are Sendable, so a copy taken under the lock is safe to keep.
final class Locked<Value: Sendable>: Sendable {
    private let mutex: Mutex<Value>

    init(_ value: Value) { mutex = Mutex(value) }

    var value: Value {
        get { mutex.withLock { $0 } }
        set { mutex.withLock { $0 = newValue } }
    }

    @discardableResult
    func withLock<Result: Sendable, Failure: Error>(
        _ body: (inout Value) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        try mutex.withLock { (value: inout sending Value) throws(Failure) -> Result in try body(&value) }
    }
}
