import Foundation

/// One retained content revision of a conversation turn. The newest revision
/// is the turn's current content; earlier revisions stay retained so an
/// amended source record never silently erases what was previously imported.
///
/// The full retained text is rich private context that lives only in
/// Reflect's Application Support sessions store, kept separate from compact
/// EvidenceEvents and from the short local display preview.
public struct TurnRevision: Codable, Hashable {
    /// Stable content reference: an opaque digest of this revision's
    /// canonical content. Identical content always yields the same
    /// revision ID, which is what makes repeated imports idempotent.
    public let revisionID: String
    /// When this revision was imported.
    public let importedAt: Date
    /// Observed time from the source record, when the source provided one.
    /// Absent times stay absent; they are never fabricated from the clock.
    public let timestamp: Date?
    /// True when the observed time is absent or approximate.
    public let timestampApproximate: Bool
    /// Full retained selected text for this revision.
    public let retainedText: String
    /// True when the source text exceeded the retention limit and was capped.
    public let retainedTextTruncated: Bool
    /// Short display preview, capped independently of retention.
    public let localPreview: String
    /// True when the preview is shorter than the retained text.
    public let previewTruncated: Bool

    public init(
        revisionID: String,
        importedAt: Date,
        timestamp: Date?,
        timestampApproximate: Bool,
        retainedText: String,
        retainedTextTruncated: Bool,
        localPreview: String,
        previewTruncated: Bool
    ) {
        self.revisionID = revisionID
        self.importedAt = importedAt
        self.timestamp = timestamp
        self.timestampApproximate = timestampApproximate
        self.retainedText = retainedText
        self.retainedTextTruncated = retainedTextTruncated
        self.localPreview = localPreview
        self.previewTruncated = previewTruncated
    }
}

/// The observed role of a conversation turn, as recorded by the source
/// format. A role label alone never proves human authorship: user-role
/// records can also carry tool-injected context.
public enum ConversationRole: String, Codable, CaseIterable, Hashable {
    case user
    case assistant
    case system
    case tool
    case reasoning
    case unknown
}

/// One normalized conversation turn inside a `WorkSession`. Turn identity is
/// stable across re-imports; content changes become new retained revisions
/// linked to the same stable turn ID. Role alone does not prove human
/// authorship; observed attribution is recorded structurally with its note.
public struct ConversationTurn: Codable, Hashable, Identifiable {
    /// Stable opaque turn identity (digest form), independent of
    /// EvidenceEvent IDs.
    public let id: String
    /// The stable ID of the owning `WorkSession`.
    public let sessionID: String
    /// Observed role from the source record.
    public let role: ConversationRole
    /// Source-provided stable turn identifier, preserved when valid.
    public let sourceTurnID: String?
    /// Private local bookkeeping: the source file the record came from.
    /// Never sent anywhere and never treated as a project or task name.
    public let sourcePath: String
    /// Source record locator (1-based line number) when known.
    public let sourceLine: Int?
    /// Order of the turn within the session's ordered turn list.
    public var sequence: Int
    /// Structural attribution recorded at import time; never asserted as
    /// human authorship.
    public let observedAttribution: Attribution
    public let observedAttributionNote: String
    /// Retained revisions in import order; the last one is current.
    public var revisions: [TurnRevision]

    public init(
        id: String,
        sessionID: String,
        role: ConversationRole,
        sourceTurnID: String?,
        sourcePath: String,
        sourceLine: Int?,
        sequence: Int,
        observedAttribution: Attribution,
        observedAttributionNote: String,
        revisions: [TurnRevision]
    ) {
        self.id = id
        self.sessionID = sessionID
        self.role = role
        self.sourceTurnID = sourceTurnID
        self.sourcePath = sourcePath
        self.sourceLine = sourceLine
        self.sequence = sequence
        self.observedAttribution = observedAttribution
        self.observedAttributionNote = observedAttributionNote
        self.revisions = revisions
    }

    /// The newest retained revision, when the turn carries one.
    public var currentRevision: TurnRevision? { revisions.last }

    /// The current revision's ID doubles as the turn's content reference.
    public var contentReference: String { currentRevision?.revisionID ?? "" }
    public var timestamp: Date? { currentRevision?.timestamp }
    public var timestampApproximate: Bool { currentRevision?.timestampApproximate ?? true }
    public var retainedText: String { currentRevision?.retainedText ?? "" }
    public var retainedTextTruncated: Bool { currentRevision?.retainedTextTruncated ?? false }
    public var localPreview: String { currentRevision?.localPreview ?? "" }
    public var previewTruncated: Bool { currentRevision?.previewTruncated ?? false }
}
