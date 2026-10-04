import Foundation

/// One bounded context item selected by `ContextRetriever`. Items are the
/// included, provider-bound unit of context: `text` carries the exact
/// provider-bound rendering (provenance label plus content, never source
/// paths or other private locators) and `byteCount` is that rendering's
/// exact UTF-8 encoded byte size, which is what budget enforcement and
/// coverage reporting count.
///
/// Provenance stays exact: observations (`observedTurn`, `observedEvent`)
/// carry the attribution as recorded at import time and are never rewritten;
/// `userCorrection` items are separate records alongside them; `selfReport`
/// items are the user's own saved answers, never promoted to observations.
/// Generated analysis output and prior inferences are never items.
public struct ContextItem: Identifiable, Hashable, Codable {
    public enum Kind: String, Codable, Hashable, CaseIterable {
        case observedTurn
        case observedEvent
        case userCorrection
        case selfReport
    }

    /// Stable context-item identity. For observations this is the stored
    /// record's own stable ID (turn or event). Corrections and self-reports
    /// get deterministic composite IDs so they never collide with the
    /// observation they relate to; the exact stored ID stays in
    /// `sourceRecordID`.
    public let id: String
    /// The exact stored record identifier this item was built from (turn ID,
    /// event ID, correction's event ID, or the report's civil-day key).
    public let sourceRecordID: String
    public let kind: Kind
    public let provenance: ClaimProvenance
    /// Observed role for turn items; nil otherwise.
    public let role: ConversationRole?
    /// Observed record type for event items; nil otherwise.
    public let eventKind: EventKind?
    /// The structural attribution exactly as recorded at import time. Never
    /// mutated by corrections, which travel as separate items.
    public let observedAttribution: Attribution?
    public let observedAttributionNote: String?
    public let observedAt: Date?
    public let timestampApproximate: Bool
    /// True when the stored retained text was already capped at import; the
    /// retrieval itself included the full stored revision.
    public let retainedTextCappedAtImport: Bool
    public let sourceKind: SourceKind?
    /// Opaque owning session ID for turn items; nil otherwise.
    public let sessionID: String?
    /// Civil-day key for self-report items; nil otherwise.
    public let dayKey: String?
    /// The exact provider-bound text of this item (label + content). Never
    /// contains source paths or other private locators.
    public var text: String
    /// True when this item was cut to fit the byte budget and labeled.
    public var truncated: Bool
    /// Exact UTF-8 encoded byte count of `text`.
    public var byteCount: Int

    public init(
        id: String,
        sourceRecordID: String,
        kind: Kind,
        provenance: ClaimProvenance,
        role: ConversationRole? = nil,
        eventKind: EventKind? = nil,
        observedAttribution: Attribution? = nil,
        observedAttributionNote: String? = nil,
        observedAt: Date? = nil,
        timestampApproximate: Bool = false,
        retainedTextCappedAtImport: Bool = false,
        sourceKind: SourceKind? = nil,
        sessionID: String? = nil,
        dayKey: String? = nil,
        text: String,
        truncated: Bool = false,
        byteCount: Int = 0
    ) {
        self.id = id
        self.sourceRecordID = sourceRecordID
        self.kind = kind
        self.provenance = provenance
        self.role = role
        self.eventKind = eventKind
        self.observedAttribution = observedAttribution
        self.observedAttributionNote = observedAttributionNote
        self.observedAt = observedAt
        self.timestampApproximate = timestampApproximate
        self.retainedTextCappedAtImport = retainedTextCappedAtImport
        self.sourceKind = sourceKind
        self.sessionID = sessionID
        self.dayKey = dayKey
        self.text = text
        self.truncated = truncated
        self.byteCount = byteCount
    }
}
