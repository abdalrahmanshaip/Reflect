import Foundation

/// Why a `ConversationResponse` was rejected before it could become a
/// durable message. Rejection is total: a malformed or unsupported response
/// is never partially repaired, and no competence conclusion is ever
/// invented to fill a validation gap. Notes are safe English — they never
/// quote payload text, IDs beyond the request's own, or provider output.
public enum ResponseValidationRejection: Error, Equatable {
    /// The answer carried no usable text.
    case emptyAnswer
    /// The response claims to answer a different request than the run that
    /// received it.
    case requestMismatch(expected: String)
    /// The response cited context item IDs that were not part of the
    /// request's actual included context. Unknown references are rejected,
    /// never stripped and never guessed.
    case unknownReferences(count: Int)

    /// Safe English note recorded on the failed request state.
    var note: String {
        switch self {
        case .emptyAnswer:
            return "The agent returned no usable answer text, so nothing was saved."
        case .requestMismatch:
            return "The agent's reply did not match this request, so it was not saved."
        case .unknownReferences(let count):
            return "The agent's reply cited \(count) context reference(s) that were not part of this request's context, so it was not saved."
        }
    }
}

/// Validates raw agent output against the request's actual context envelope
/// before anything is persisted. Validation checks structure and reference
/// grounding only: it never judges the truth of the text, never scores the
/// user, and never promotes generated content into observations.
public enum ResponseValidator {
    /// Throws `ResponseValidationRejection` when the response cannot be
    /// persisted. A valid response has non-empty answer text, matches the
    /// run's request ID, and cites only context items that were actually
    /// included in the envelope (truncated items are included items).
    public static func validate(
        _ response: ConversationResponse,
        expectedRequestID: String,
        envelope: ContextEnvelope
    ) throws {
        guard !response.answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ResponseValidationRejection.emptyAnswer
        }
        guard response.requestID == expectedRequestID else {
            throw ResponseValidationRejection.requestMismatch(expected: expectedRequestID)
        }
        let includedIDs = Set(envelope.items.map(\.id))
        let unknown = response.referencedContextItemIDs.filter { !includedIDs.contains($0) }
        guard unknown.isEmpty else {
            throw ResponseValidationRejection.unknownReferences(count: unknown.count)
        }
    }
}
