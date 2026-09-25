import Foundation

enum CompletionReason {
    static func validate(_ reason: String?, allowed: Set<String>) throws {
        // A missing reason cannot establish that a non-streaming reply completed.
        guard let reason, allowed.contains(reason) else { throw RefinerError.incompleteOutput }
    }
}
