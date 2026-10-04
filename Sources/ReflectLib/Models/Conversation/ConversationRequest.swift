import Foundation

/// An explicit conversation request, created only by a deliberate user send
/// action. One request ID travels through context building, invocation,
/// response validation, persistence, and UI status, so a response can only
/// ever apply to its originating conversation and request.
///
/// `followUpTurns` carries the conversation's own durable prior exchange
/// (loaded from the conversations store, never re-derived from any source
/// history) so a follow-up can continue where the conversation left off. The
/// approved evidence basis travels separately in the context envelope.
public struct ConversationRequest: Codable, Hashable {
    /// App-owned stable identity: a `UUID` string in the shared plain
    /// `String` ID type (accepted M1 identity rules).
    public let id: String
    public let conversationID: String
    /// The user's question text, exactly as submitted (whitespace-trimmed).
    public let question: String
    public let requestedAt: Date
    /// The durable prior exchange of this conversation, in persisted order,
    /// bounded to the most recent turns. Empty for a conversation's first
    /// message.
    public let followUpTurns: [ConversationFollowUpTurn]

    public init(
        id: String,
        conversationID: String,
        question: String,
        requestedAt: Date,
        followUpTurns: [ConversationFollowUpTurn] = []
    ) {
        self.id = id
        self.conversationID = conversationID
        self.question = question
        self.requestedAt = requestedAt
        self.followUpTurns = followUpTurns
    }
}

/// One prior durable exchange turn made available for follow-up continuity.
/// It carries only the speaker and text of Reflect's own stored conversation
/// message — never source paths, locators, or content reread from history.
public struct ConversationFollowUpTurn: Codable, Hashable {
    public let speaker: ConversationSpeaker
    public let text: String

    public init(speaker: ConversationSpeaker, text: String) {
        self.speaker = speaker
        self.text = text
    }
}
