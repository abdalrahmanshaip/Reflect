/// One suggested question attached to a day. IDs stay stable across launches so
/// saved answers remain attached to the same question. Wording is plain; the
/// counts it was derived from live in `basis`, not in the question itself.
public struct SuggestedQuestion: Identifiable, Equatable, Hashable {
    public let id: String
    public let text: String
    /// Names the records the question came from. Shown under the question.
    public let basis: String

    public init(id: String, text: String, basis: String) {
        self.id = id
        self.text = text
        self.basis = basis
    }
}

/// A supporting fact line under the observed sentence. The marker selects the
/// legend glyph: observed facts use the square, user corrections the dot.
public struct OverviewFact: Identifiable, Equatable, Hashable {
    public enum Marker: Equatable, Hashable {
        case observed
        case correction
    }

    public let marker: Marker
    public let text: String

    public var id: String { text }

    public init(marker: Marker, text: String) {
        self.marker = marker
        self.text = text
    }
}

/// The factual daily summary behind the redesigned Today page: one observed
/// sentence, supporting facts, and the deterministic suggested questions.
/// Everything here is derived from imported evidence; no field claims
/// authorship or skill, and project names appear only if imported metadata
/// ever establishes one.
public struct DayOverview: Equatable {
    public let dayKey: String
    public let hasEvidence: Bool
    public let eventCount: Int
    /// Plain grounded sentence, present only when at least one record is imported.
    public let observedSentence: String?
    public let facts: [OverviewFact]
    /// Empty unless the day meets the question threshold. The first entry is
    /// the primary question; the rest are alternates for "try another".
    public let questions: [SuggestedQuestion]
    /// Honest status note when there is no evidence or too little for a question.
    public let statusNote: String?
    public let hasReport: Bool
    /// True only when a saved user answer has nonblank content. Generated
    /// narrative drafts and analysis results are never counted as reflection.
    public let reflected: Bool

    public init(
        dayKey: String,
        hasEvidence: Bool,
        eventCount: Int,
        observedSentence: String?,
        facts: [OverviewFact],
        questions: [SuggestedQuestion],
        statusNote: String?,
        hasReport: Bool,
        reflected: Bool
    ) {
        self.dayKey = dayKey
        self.hasEvidence = hasEvidence
        self.eventCount = eventCount
        self.observedSentence = observedSentence
        self.facts = facts
        self.questions = questions
        self.statusNote = statusNote
        self.hasReport = hasReport
        self.reflected = reflected
    }
}

/// A sidebar "Earlier" row: a day the user can revisit. Days exist here if they
/// have imported events or a saved report (report-only days included).
public struct RecentDay: Identifiable, Equatable, Hashable {
    public let dayKey: String
    public let eventCount: Int
    public let hasReport: Bool
    public let reflected: Bool

    public var id: String { dayKey }

    /// Recorded events and no reflection yet are distinct from days with no
    /// records at all, so the sidebar never implies missing evidence.
    public var statusLabel: String {
        if reflected { return "Reflected" }
        if eventCount > 0 { return "Not yet" }
        return "No records"
    }

    public init(dayKey: String, eventCount: Int, hasReport: Bool, reflected: Bool) {
        self.dayKey = dayKey
        self.eventCount = eventCount
        self.hasReport = hasReport
        self.reflected = reflected
    }
}
