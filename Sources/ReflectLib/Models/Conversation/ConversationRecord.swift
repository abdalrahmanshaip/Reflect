import Foundation

/// A durable Reflect conversation: identity, ordering metadata, message IDs,
/// and the conversation's unsent composer draft. The record carries no
/// message text itself; messages live alongside it in the same stored
/// conversation so one atomic store write always moves record and messages
/// together.
public struct ConversationRecord: Codable, Hashable, Identifiable {
    /// App-owned stable identity: a `UUID` string in the shared plain
    /// `String` ID type (accepted M1 identity rules).
    public let id: String
    public let createdAt: Date
    public var updatedAt: Date
    /// Persisted message IDs in persisted order. A user message appears here
    /// only after its write succeeded, and an assistant message only after
    /// its validated response write succeeded.
    public var messageIDs: [String]
    /// The conversation's unsent composer draft, persisted so route changes
    /// and relaunches keep the user's text. Draft text is never a saved
    /// message.
    public var draftText: String?
    public var draftUpdatedAt: Date?

    public init(
        id: String,
        createdAt: Date,
        updatedAt: Date,
        messageIDs: [String] = [],
        draftText: String? = nil,
        draftUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messageIDs = messageIDs
        self.draftText = draftText
        self.draftUpdatedAt = draftUpdatedAt
    }
}

/// The persisted unit of the versioned `conversations` store: one record
/// with all of its messages. Keeping them together means every durable
/// transition (saved user message, saved response, draft update) is one
/// atomic envelope replacement — a partial conversation can never be
/// published.
public struct StoredConversation: Codable, Hashable {
    public var record: ConversationRecord
    public var messages: [ConversationMessage]

    public init(record: ConversationRecord, messages: [ConversationMessage]) {
        self.record = record
        self.messages = messages
    }
}
