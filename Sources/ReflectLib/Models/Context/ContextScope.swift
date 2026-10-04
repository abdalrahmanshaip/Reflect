import Foundation

/// Optional restrictions on which stored records a retrieval may consider.
/// A scope narrows Reflect's own persisted stores; it never authorizes a
/// live read of any source history. Nil fields mean unrestricted.
public struct ContextScope: Codable, Hashable {
    /// Restrict to these stored source kinds. Self-reports (which have no
    /// source kind) are unaffected by this field.
    public let sourceKinds: Set<SourceKind>?
    /// Restrict to records with an observed time inside this interval.
    /// Records whose time is unknown cannot be placed and are reported as
    /// omitted rather than silently dropped.
    public let dateInterval: DateInterval?
    /// Restrict to these explicit stored record IDs (turn, event, report day
    /// key, or correction event ID).
    public let referenceIDs: Set<String>?

    public init(
        sourceKinds: Set<SourceKind>? = nil,
        dateInterval: DateInterval? = nil,
        referenceIDs: Set<String>? = nil
    ) {
        self.sourceKinds = sourceKinds
        self.dateInterval = dateInterval
        self.referenceIDs = referenceIDs
    }
}
