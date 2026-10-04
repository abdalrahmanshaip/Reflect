import Foundation

/// The observed-time span of the included items. Absent dates stay nil and
/// approximate or missing times are flagged, never smoothed over.
public struct ContextDateCoverage: Equatable, Hashable, Codable {
    public let earliest: Date?
    public let latest: Date?
    public let includesApproximateOrMissingTimes: Bool

    public init(earliest: Date?, latest: Date?, includesApproximateOrMissingTimes: Bool) {
        self.earliest = earliest
        self.latest = latest
        self.includesApproximateOrMissingTimes = includesApproximateOrMissingTimes
    }
}

/// The bounded context produced by one deterministic retrieval. It pairs the
/// included, provider-bound items with honest coverage: the M1
/// `BoundedContextDescriptor` (budget plus achieved coverage), the omitted
/// and truncated item IDs, earlier-example availability, stores that do not
/// exist yet, date/source coverage, and safe English uncertainty notes.
///
/// The envelope carries no source paths or other private locators and never
/// contains generated analysis output or prior inferences promoted as
/// observations. It is a local value: serializing it for a provider is a
/// separate, explicit step (`ContextSerializer`).
public struct ContextEnvelope: Equatable, Hashable, Codable {
    public static let schemaVersion = "reflect-context/v1"

    public let schema: String
    public let generatedAt: Date
    public let requestTerms: [String]
    public let comparisonRequested: Bool
    /// Included items in deterministic inclusion order (truncated items are
    /// included items and also counted in `truncatedItemIDs`).
    public let items: [ContextItem]
    /// IDs of relevant items left out entirely (privacy exclusions, budget
    /// omissions, unplaceable records, corrections that did not fit).
    public let omittedItemIDs: [String]
    /// IDs of items included only partially under the byte budget.
    public let truncatedItemIDs: [String]
    public let descriptor: BoundedContextDescriptor
    public let earlierExamples: EarlierExamplesCoverage
    public let outcome: ContextOutcomeKind
    /// Stores that do not exist on disk yet (the valid first-run state),
    /// distinct from present-but-empty and from damaged (which throws).
    public let missingStores: [StoreName]
    public let dateCoverage: ContextDateCoverage
    /// Distinct source kinds among included items, sorted by raw value.
    public let sourceKinds: [SourceKind]
    /// Safe English notes about exclusions, gaps, and unknowns. They never
    /// contain payload text, paths, or secret values.
    public let uncertaintyNotes: [String]

    public init(
        generatedAt: Date,
        requestTerms: [String],
        comparisonRequested: Bool,
        items: [ContextItem],
        omittedItemIDs: [String],
        truncatedItemIDs: [String],
        descriptor: BoundedContextDescriptor,
        earlierExamples: EarlierExamplesCoverage,
        outcome: ContextOutcomeKind,
        missingStores: [StoreName],
        dateCoverage: ContextDateCoverage,
        sourceKinds: [SourceKind],
        uncertaintyNotes: [String]
    ) {
        self.schema = Self.schemaVersion
        self.generatedAt = generatedAt
        self.requestTerms = requestTerms
        self.comparisonRequested = comparisonRequested
        self.items = items
        self.omittedItemIDs = omittedItemIDs
        self.truncatedItemIDs = truncatedItemIDs
        self.descriptor = descriptor
        self.earlierExamples = earlierExamples
        self.outcome = outcome
        self.missingStores = missingStores
        self.dateCoverage = dateCoverage
        self.sourceKinds = sourceKinds
        self.uncertaintyNotes = uncertaintyNotes
    }
}
