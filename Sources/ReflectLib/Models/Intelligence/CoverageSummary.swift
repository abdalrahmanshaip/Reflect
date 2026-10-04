import Foundation

/// What a session record actually covers, and what it does not. Counts are
/// derived from the session's retained turns so they stay accurate across
/// repeated imports; scan facts that cannot be maintained cumulatively
/// (malformed or skipped source lines) are reported per import and persist
/// here only as uncertainty notes. Unknown or missing context is represented
/// by explicit flags and absent dates, never by zeros pretending to be
/// observations.
public struct CoverageSummary: Codable, Hashable {
    /// Number of ordered turns currently retained in the session.
    public var turnCount: Int
    /// Retained turns whose current observed time is absent or approximate.
    public var approximateTimestampTurnCount: Int
    /// Retained turns whose retained text was capped by the retention limit.
    public var truncatedRetainedTextTurnCount: Int
    /// True when no valid source-provided session identity was found, so the
    /// session identity was derived from the source file instead.
    public var missingSessionIdentity: Bool
    /// Earliest and latest observed turn times; nil when no turn carried one.
    public var firstRecordedAt: Date?
    public var lastRecordedAt: Date?
    /// Parser/source-format version that last updated this session record.
    public var parserVersion: String
    /// Durable notes about parser and source-format uncertainty (for example,
    /// skipped malformed or unrecognized source lines). Empty when none were
    /// observed.
    public var parserUncertaintyNotes: [String]

    public init(
        turnCount: Int,
        approximateTimestampTurnCount: Int,
        truncatedRetainedTextTurnCount: Int,
        missingSessionIdentity: Bool,
        firstRecordedAt: Date?,
        lastRecordedAt: Date?,
        parserVersion: String,
        parserUncertaintyNotes: [String]
    ) {
        self.turnCount = turnCount
        self.approximateTimestampTurnCount = approximateTimestampTurnCount
        self.truncatedRetainedTextTurnCount = truncatedRetainedTextTurnCount
        self.missingSessionIdentity = missingSessionIdentity
        self.firstRecordedAt = firstRecordedAt
        self.lastRecordedAt = lastRecordedAt
        self.parserVersion = parserVersion
        self.parserUncertaintyNotes = parserUncertaintyNotes
    }

    /// Derives count-based coverage from a session's retained turns.
    /// Identity, parser version, and uncertainty notes come from the caller
    /// because they describe the import, not the turns.
    public static func derived(
        from turns: [ConversationTurn],
        missingSessionIdentity: Bool,
        parserVersion: String,
        parserUncertaintyNotes: [String]
    ) -> CoverageSummary {
        let currentRevisions = turns.compactMap { $0.revisions.last }
        let timestamps = currentRevisions.compactMap(\.timestamp)
        return CoverageSummary(
            turnCount: turns.count,
            approximateTimestampTurnCount: currentRevisions.filter(\.timestampApproximate).count,
            truncatedRetainedTextTurnCount: currentRevisions.filter(\.retainedTextTruncated).count,
            missingSessionIdentity: missingSessionIdentity,
            firstRecordedAt: timestamps.min(),
            lastRecordedAt: timestamps.max(),
            parserVersion: parserVersion,
            parserUncertaintyNotes: parserUncertaintyNotes
        )
    }

    /// Merges durable uncertainty notes from a newer import into this
    /// summary, preserving order and dropping duplicates. Everything else is
    /// recomputed from retained turns, so this method only unions notes.
    func unioningUncertaintyNotes(_ other: CoverageSummary) -> CoverageSummary {
        var merged = self
        for note in other.parserUncertaintyNotes where !merged.parserUncertaintyNotes.contains(note) {
            merged.parserUncertaintyNotes.append(note)
        }
        return merged
    }
}
