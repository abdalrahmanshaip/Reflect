import Foundation

/// A normalized work session with ordered conversation turns, per the shared
/// M2 contract. Sessions live in the separate versioned `sessions` store with
/// their own stable identity, independent of EvidenceEvents. Titles and
/// projects are only ever set from source-established values; unknown stays
/// nil and is never inferred from file paths or timestamps.
public struct WorkSession: Codable, Hashable {
    /// Stable opaque session identity (digest form), independent of
    /// EvidenceEvent IDs. Source-provided session IDs are preserved in
    /// `sourceSessionID`; this ID is Reflect's own stable key.
    public let id: String
    public let sourceKind: SourceKind
    /// The source-established session identifier when the source provided a
    /// valid one; nil otherwise.
    public let sourceSessionID: String?
    /// Source-established title, when the source provides one; unknown stays nil.
    public let title: String?
    /// Source-established project, when the source provides one; unknown stays nil.
    public let project: String?
    /// Bumps by one on every import that changed this session's content.
    public var importRevision: Int
    public var firstImportedAt: Date
    public var lastImportedAt: Date
    /// Earliest observed time (session start record, else earliest turn).
    /// Approximate only when its source was approximate; absent stays nil.
    public var startedAt: Date?
    public var startedAtApproximate: Bool
    /// Latest observed turn time; nil when no turn carried a time.
    public var lastActivityAt: Date?
    /// Ordered turns. Appends extend the order; amendments revise in place.
    public var turns: [ConversationTurn]
    public var coverage: CoverageSummary

    public init(
        id: String,
        sourceKind: SourceKind,
        sourceSessionID: String?,
        title: String?,
        project: String?,
        importRevision: Int,
        firstImportedAt: Date,
        lastImportedAt: Date,
        startedAt: Date?,
        startedAtApproximate: Bool,
        lastActivityAt: Date?,
        turns: [ConversationTurn],
        coverage: CoverageSummary
    ) {
        self.id = id
        self.sourceKind = sourceKind
        self.sourceSessionID = sourceSessionID
        self.title = title
        self.project = project
        self.importRevision = importRevision
        self.firstImportedAt = firstImportedAt
        self.lastImportedAt = lastImportedAt
        self.startedAt = startedAt
        self.startedAtApproximate = startedAtApproximate
        self.lastActivityAt = lastActivityAt
        self.turns = turns
        self.coverage = coverage
    }

    /// The session's ordered stable turn IDs; order matches `turns`.
    public var turnIDs: [String] { turns.map(\.id) }
}
