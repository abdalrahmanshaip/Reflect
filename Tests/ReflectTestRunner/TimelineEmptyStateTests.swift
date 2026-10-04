import Foundation
@testable import ReflectLib

struct TimelineEmptyStateTests {
    static let suiteName = "TimelineEmptyStateTests"

    func emptyStoreKeepsImportGuidance() throws {
        let state = TimelineEmptyState.resolve(totalEventCount: 0, matchingEventCount: 0)
        try expectEqual(state, .emptyStore)
        try expectEqual(state?.title, "No events yet")
        try expectFalse(state?.offersClearFilters == true)
        try expectTrue(state?.detail.contains("Imports run only when you start them") == true)
    }

    func filteredNoMatchesOffersClearFilters() throws {
        let state = TimelineEmptyState.resolve(totalEventCount: 12, matchingEventCount: 0)
        try expectEqual(state, .filteredNoMatches)
        try expectEqual(state?.title, "No matching records")
        try expectTrue(state?.offersClearFilters == true)
        try expectTrue(state?.detail.contains("filters") == true)
    }

    func matchingRecordsNeedNoEmptyState() throws {
        try expectNil(TimelineEmptyState.resolve(totalEventCount: 12, matchingEventCount: 3))
    }

    func clearResetsEveryTimelineFilter() throws {
        var filters = TimelineFilterSelection(
            dayKey: "2026-01-05",
            source: .codex,
            kind: .agentMessage
        )
        try expectTrue(filters.isActive)

        filters.clear()

        try expectEqual(filters, TimelineFilterSelection())
        try expectFalse(filters.isActive)
    }

    static var entries: [TestEntry] {
        let tests = TimelineEmptyStateTests()
        return [
            TestEntry(suite: suiteName, name: "emptyStoreKeepsImportGuidance") {
                try tests.emptyStoreKeepsImportGuidance()
            },
            TestEntry(suite: suiteName, name: "filteredNoMatchesOffersClearFilters") {
                try tests.filteredNoMatchesOffersClearFilters()
            },
            TestEntry(suite: suiteName, name: "matchingRecordsNeedNoEmptyState") {
                try tests.matchingRecordsNeedNoEmptyState()
            },
            TestEntry(suite: suiteName, name: "clearResetsEveryTimelineFilter") {
                try tests.clearResetsEveryTimelineFilter()
            }
        ]
    }
}
