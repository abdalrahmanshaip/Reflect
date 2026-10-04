import Foundation

extension BoundedContextBudget {
    /// The initial proposed retrieval caps from plan 05: at most 32,768 UTF-8
    /// content bytes, 24 included items, and 12 neighboring turns per
    /// selected session window. These are engineering test values, not
    /// user-approved product constants; tests inject smaller limits.
    public static let retrievalDefault: BoundedContextBudget = try! BoundedContextBudget(
        maxItemCount: 24,
        maxByteCount: 32_768,
        maxTurnCount: 12
    )
}

/// A deterministic, transparent retrieval request over Reflect's own
/// persisted stores. `terms` drive relevance (empty terms select by recency);
/// `requestsEarlierRecentComparison` asks for both relevant earlier and
/// recent examples so change over time can be assessed honestly;
/// `scope` optionally narrows the stored records considered.
public struct ContextRetrievalRequest: Hashable {
    public let terms: [String]
    public let requestsEarlierRecentComparison: Bool
    public let scope: ContextScope?
    public let budget: BoundedContextBudget

    public init(
        terms: [String],
        requestsEarlierRecentComparison: Bool = false,
        scope: ContextScope? = nil,
        budget: BoundedContextBudget = .retrievalDefault
    ) {
        self.terms = terms
        self.requestsEarlierRecentComparison = requestsEarlierRecentComparison
        self.scope = scope
        self.budget = budget
    }
}

/// Whether relevant earlier examples were available for an
/// earlier-versus-recent comparison. The states are exactly distinct so a
/// missing or unassessable comparison is never presented as evidence of
/// change (or of no change).
public enum EarlierExamplesCoverage: Equatable, Hashable, Codable {
    /// The request did not ask for a comparison.
    case notRequested
    /// Earlier examples existed; this many were included under the budget.
    case included(Int)
    /// Relevant stored history exists, but nothing qualifies as earlier, so
    /// no comparison basis exists yet.
    case missing
    /// Relevant records exist but none carry reliable observed times, so an
    /// earlier-versus-recent split is not assessable.
    case notAssessable
}

/// The overall retrieval outcome. The states are exactly distinct so an
/// empty result can never be confused with relevant history that was
/// excluded, and a damaged store never produces an envelope at all
/// (retrieval throws instead).
public enum ContextOutcomeKind: Equatable, Hashable, Codable {
    /// At least one item was included.
    case historyIncluded
    /// Stores were readable, but no stored record matched the request.
    case noRelevantHistory
    /// Relevant stored records existed, but none could be included (for
    /// example, every one was conservatively excluded by a privacy screen).
    case relevantHistoryExcluded
}
