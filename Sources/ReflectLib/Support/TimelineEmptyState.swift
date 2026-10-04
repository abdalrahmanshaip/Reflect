import Foundation

/// The three filters shown by All Records. Keeping their reset behavior in a
/// small value type makes the clear action explicit and easy to verify.
struct TimelineFilterSelection: Equatable {
    var dayKey: String? = nil
    var source: SourceKind? = nil
    var kind: EventKind? = nil

    var isActive: Bool {
        dayKey != nil || source != nil || kind != nil
    }

    mutating func clear() {
        dayKey = nil
        source = nil
        kind = nil
    }
}

/// Honest All Records empty states. A filter miss is only reported when the
/// store contains evidence; a genuinely empty store keeps its import guidance.
enum TimelineEmptyState: Equatable {
    case emptyStore
    case filteredNoMatches

    var title: String {
        switch self {
        case .emptyStore: return "No events yet"
        case .filteredNoMatches: return "No matching records"
        }
    }

    var detail: String {
        switch self {
        case .emptyStore:
            return "Imports run only when you start them in Sources. Repeated imports are deduplicated."
        case .filteredNoMatches:
            return "No records match these filters. Clear filters to show all records."
        }
    }

    var offersClearFilters: Bool {
        self == .filteredNoMatches
    }

    static func resolve(totalEventCount: Int, matchingEventCount: Int) -> Self? {
        guard matchingEventCount == 0 else { return nil }
        return totalEventCount == 0 ? .emptyStore : .filteredNoMatches
    }
}
