import Foundation

// M1 shared contract vocabulary. These types define the meaning of provenance,
// confidence, and capability reporting across Reflect's stores and future
// services. Milestone M1 defines the contracts only: no consumer UI or service
// is included yet. Existing record schemas and their identifiers are unchanged.

/// Where a claim's content comes from. The four meanings are exactly distinct:
///
/// - `observed`: a structural fact recorded at import time (for example, which
///   account produced a message). It never asserts human authorship.
/// - `inferred`: the app's own conclusion derived from observations. It is
///   always separable from what was observed and may be wrong.
/// - `selfReport`: a statement the user made about themselves, taken as a
///   report rather than as verified fact.
/// - `userCorrection`: the user's explicit override of a previously recorded
///   value. A correction is its own provenance and never mutates the
///   observation it corrects; observations stay immutable so corrections
///   survive re-imports and can themselves be revised or withdrawn.
public enum ClaimProvenance: String, Codable, CaseIterable, Hashable {
    case observed
    case inferred
    case selfReport = "self_report"
    case userCorrection = "user_correction"
}

/// Qualitative confidence in a claim. The vocabulary is deliberately small and
/// ordered, and there are no numeric scores: Reflect shows honest qualitative
/// language or "insufficient evidence" instead of fabricated percentages.
///
/// Ordering is by assessment strength only. `insufficientEvidence` is the
/// explicit below-threshold state meaning "not assessable from the evidence
/// so far"; it is a real outcome, never an error or an empty value.
public enum ClaimConfidence: String, Codable, CaseIterable, Hashable, Comparable {
    case insufficientEvidence = "insufficient_evidence"
    case low
    case moderate
    case high

    private var assessmentRank: Int {
        switch self {
        case .insufficientEvidence: return 0
        case .low: return 1
        case .moderate: return 2
        case .high: return 3
        }
    }

    public static func < (lhs: ClaimConfidence, rhs: ClaimConfidence) -> Bool {
        lhs.assessmentRank < rhs.assessmentRank
    }
}

/// Whether a capability (for example, a source or an analysis runner) is
/// usable right now. The states are exactly distinct:
///
/// - `available`: detected and usable. Detection alone does not imply that a
///   format or contract was verified; anything not yet verified must be
///   reported as `unverified` instead.
/// - `unavailable`: not detected or otherwise not usable on this machine.
/// - `unverified`: present, but not yet verified safe/compatible to use.
/// - `disabled`: present but explicitly turned off by the user.
public enum CapabilityAvailability: String, Codable, CaseIterable, Hashable {
    case available
    case unavailable
    case unverified
    case disabled
}

public extension StoreName {
    /// Current on-disk schema version of this store's JSON shape. Store
    /// identity is stable across versions: each store keeps its file name,
    /// and every store currently sits at version 1. Future shape changes bump
    /// the version per store so readers can branch without renaming files.
    var schemaVersion: Int {
        switch self {
        case .events: return 1
        case .corrections: return 1
        case .reports: return 1
        case .settings: return 1
        case .manifests: return 1
        case .sessions: return 1
        case .conversations: return 1
        }
    }
}
