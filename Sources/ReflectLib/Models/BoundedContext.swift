import Foundation

// M1 bounded-context metadata contracts. These types describe only the size
// contract of a bounded context (its explicit positive budget) and the
// coverage it actually achieved. They are metadata only: no context content,
// no retrieval algorithm, no source reading, and no AI invocation is defined
// or recorded here. Validation runs both at construction and at decoding, so
// a corrupt persisted descriptor can never bypass the invariants and reappear
// as a valid in-memory value.

/// Which maximum of a `BoundedContextBudget` was rejected.
public enum BoundedContextBudgetField: String, Hashable {
    case itemCount
    case byteCount
    case turnCount
}

/// Which count of a `BoundedContextCoverage` was rejected.
public enum BoundedContextCoverageField: String, Hashable {
    case includedItemCount
    case omittedItemCount
    case truncatedItemCount
    case includedByteCount
    case includedTurnCount
}

/// Why bounded-context metadata was rejected. Coverage counts must be
/// nonnegative, budget maxima must be strictly positive, included totals may
/// never exceed the paired budget's maxima, and the coverage `state` must
/// agree with its counts.
public enum BoundedContextValidationError: Error, Equatable {
    case nonPositiveMaximum(BoundedContextBudgetField)
    case negativeCount(BoundedContextCoverageField)
    case includedExceedsMaximum(BoundedContextCoverageField, included: Int, maximum: Int)
    /// The coverage `state` contradicted its counts, for example `complete`
    /// with omitted items, `partial` with nothing omitted or truncated, or
    /// `unavailable` with included content.
    case stateInconsistentWithCounts(SourceCoverageState)
}

/// The explicit positive budget a bounded context was built within: the
/// maximum number of items, UTF-8 encoded bytes, and conversation turns it
/// may include. Every maximum must be strictly positive — a budget of zero
/// allows nothing and is not a valid state.
public struct BoundedContextBudget: Equatable, Hashable, Codable {
    public let maxItemCount: Int
    public let maxByteCount: Int
    public let maxTurnCount: Int

    /// Direct construction with an explicit positive budget.
    public init(maxItemCount: Int, maxByteCount: Int, maxTurnCount: Int) throws {
        guard maxItemCount > 0 else {
            throw BoundedContextValidationError.nonPositiveMaximum(.itemCount)
        }
        guard maxByteCount > 0 else {
            throw BoundedContextValidationError.nonPositiveMaximum(.byteCount)
        }
        guard maxTurnCount > 0 else {
            throw BoundedContextValidationError.nonPositiveMaximum(.turnCount)
        }
        self.maxItemCount = maxItemCount
        self.maxByteCount = maxByteCount
        self.maxTurnCount = maxTurnCount
    }

    private enum CodingKeys: String, CodingKey {
        case maxItemCount
        case maxByteCount
        case maxTurnCount
    }

    /// Decoding revalidates every persisted maximum: a corrupt or hand-edited
    /// persisted budget is rejected instead of trusted.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                maxItemCount: try container.decode(Int.self, forKey: .maxItemCount),
                maxByteCount: try container.decode(Int.self, forKey: .maxByteCount),
                maxTurnCount: try container.decode(Int.self, forKey: .maxTurnCount)
            )
        } catch let error as BoundedContextValidationError {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "BoundedContextBudget rejected an out-of-range persisted maximum.",
                    underlyingError: error
                )
            )
        }
    }
}

/// Whether a bounded context covered its relevant source material. The states
/// are exactly distinct, and each carries an exact count relation that
/// `BoundedContextCoverage` enforces:
///
/// - `complete`: every relevant source item was included; nothing was omitted
///   or truncated. Requires `omittedItemCount == 0` and `truncatedItemCount == 0`.
/// - `partial`: some relevant items were omitted or truncated. Requires at
///   least one of `omittedItemCount` or `truncatedItemCount` to be positive.
/// - `unavailable`: the underlying source could not be read at all, so
///   nothing could be included. Requires every count to be zero: no source
///   content was read and the exact coverage counts are unknown.
/// - `unknown`: coverage was not assessed (or not yet assessed). This is a
///   real outcome, never an error or an empty value. No count relation is
///   enforced.
public enum SourceCoverageState: String, Codable, CaseIterable, Hashable {
    case complete
    case partial
    case unavailable
    case unknown
}

/// Coverage metadata describing what a bounded context actually included,
/// in item, byte, and turn terms. Byte counts always measure UTF-8 encoded
/// bytes of the included content. Counts are metadata only: no item content,
/// ordering, or retrieval algorithm is recorded.
///
/// The `state` must agree with the counts: `complete` allows no omitted or
/// truncated items, `partial` requires at least one omitted or truncated
/// item, and `unavailable` allows only all-zero counts (no source content was
/// read). `unknown` carries no count relation. Violations are rejected both
/// at construction and at decoding.
public struct BoundedContextCoverage: Equatable, Hashable, Codable {
    /// Items made part of the context.
    public let includedItemCount: Int
    /// Relevant items left out entirely.
    public let omittedItemCount: Int
    /// Items only partially included.
    public let truncatedItemCount: Int
    /// Size of the included content in UTF-8 encoded bytes.
    public let includedByteCount: Int
    /// Conversation turns included.
    public let includedTurnCount: Int
    /// The overall source coverage state.
    public let state: SourceCoverageState

    /// Direct construction with explicit, nonnegative counts whose state/count
    /// combination is consistent. There is no negative or "unset" count
    /// sentinel; an unassessed coverage is expressed by `state: .unknown`,
    /// never by magic numbers.
    public init(
        includedItemCount: Int,
        omittedItemCount: Int,
        truncatedItemCount: Int,
        includedByteCount: Int,
        includedTurnCount: Int,
        state: SourceCoverageState
    ) throws {
        guard includedItemCount >= 0 else {
            throw BoundedContextValidationError.negativeCount(.includedItemCount)
        }
        guard omittedItemCount >= 0 else {
            throw BoundedContextValidationError.negativeCount(.omittedItemCount)
        }
        guard truncatedItemCount >= 0 else {
            throw BoundedContextValidationError.negativeCount(.truncatedItemCount)
        }
        guard includedByteCount >= 0 else {
            throw BoundedContextValidationError.negativeCount(.includedByteCount)
        }
        guard includedTurnCount >= 0 else {
            throw BoundedContextValidationError.negativeCount(.includedTurnCount)
        }
        switch state {
        case .complete:
            guard omittedItemCount == 0, truncatedItemCount == 0 else {
                throw BoundedContextValidationError.stateInconsistentWithCounts(.complete)
            }
        case .partial:
            guard omittedItemCount > 0 || truncatedItemCount > 0 else {
                throw BoundedContextValidationError.stateInconsistentWithCounts(.partial)
            }
        case .unavailable:
            guard includedItemCount == 0, includedByteCount == 0, includedTurnCount == 0,
                  omittedItemCount == 0, truncatedItemCount == 0 else {
                throw BoundedContextValidationError.stateInconsistentWithCounts(.unavailable)
            }
        case .unknown:
            break
        }
        self.includedItemCount = includedItemCount
        self.omittedItemCount = omittedItemCount
        self.truncatedItemCount = truncatedItemCount
        self.includedByteCount = includedByteCount
        self.includedTurnCount = includedTurnCount
        self.state = state
    }

    private enum CodingKeys: String, CodingKey {
        case includedItemCount
        case omittedItemCount
        case truncatedItemCount
        case includedByteCount
        case includedTurnCount
        case state
    }

    /// Decoding revalidates every persisted count and the state/count
    /// combination: a corrupt persisted coverage is rejected instead of
    /// trusted.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                includedItemCount: try container.decode(Int.self, forKey: .includedItemCount),
                omittedItemCount: try container.decode(Int.self, forKey: .omittedItemCount),
                truncatedItemCount: try container.decode(Int.self, forKey: .truncatedItemCount),
                includedByteCount: try container.decode(Int.self, forKey: .includedByteCount),
                includedTurnCount: try container.decode(Int.self, forKey: .includedTurnCount),
                state: try container.decode(SourceCoverageState.self, forKey: .state)
            )
        } catch let error as BoundedContextValidationError {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "BoundedContextCoverage rejected an invalid persisted count or state/count combination.",
                    underlyingError: error
                )
            )
        }
    }
}

/// A bounded-context descriptor pairing one explicit budget with the coverage
/// achieved under it. The descriptor enforces the budget: included item,
/// byte, and turn totals may never exceed the paired maxima, both when
/// constructed directly and when decoded from persisted data. It also
/// inherits the coverage state/count consistency rules: its coverage is
/// validated by `BoundedContextCoverage` itself on every construction and
/// decoding path.
public struct BoundedContextDescriptor: Equatable, Hashable, Codable {
    public let budget: BoundedContextBudget
    public let coverage: BoundedContextCoverage

    /// Direct construction with an explicit budget/coverage pair.
    public init(budget: BoundedContextBudget, coverage: BoundedContextCoverage) throws {
        if coverage.includedItemCount > budget.maxItemCount {
            throw BoundedContextValidationError.includedExceedsMaximum(
                .includedItemCount,
                included: coverage.includedItemCount,
                maximum: budget.maxItemCount
            )
        }
        if coverage.includedByteCount > budget.maxByteCount {
            throw BoundedContextValidationError.includedExceedsMaximum(
                .includedByteCount,
                included: coverage.includedByteCount,
                maximum: budget.maxByteCount
            )
        }
        if coverage.includedTurnCount > budget.maxTurnCount {
            throw BoundedContextValidationError.includedExceedsMaximum(
                .includedTurnCount,
                included: coverage.includedTurnCount,
                maximum: budget.maxTurnCount
            )
        }
        self.budget = budget
        self.coverage = coverage
    }

    private enum CodingKeys: String, CodingKey {
        case budget
        case coverage
    }

    /// Decoding decodes both parts through their own validating decoders and
    /// then re-enforces the included<=maximum bounds, so a corrupt persisted
    /// descriptor can never bypass the budget invariants.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                budget: try container.decode(BoundedContextBudget.self, forKey: .budget),
                coverage: try container.decode(BoundedContextCoverage.self, forKey: .coverage)
            )
        } catch let error as BoundedContextValidationError {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "BoundedContextDescriptor rejected persisted metadata outside its budget.",
                    underlyingError: error
                )
            )
        }
    }
}
