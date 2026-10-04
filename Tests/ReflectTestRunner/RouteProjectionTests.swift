import Foundation
@testable import ReflectLib

struct RouteProjectionTests {
    static let suiteName = "RouteProjectionTests"

    func timelineFiltersAndGroupsMatchReferenceForAllCombinations() throws {
        let fixture = SyntheticPerformanceFixture.make(count: 21)
        let index = EventProjectionIndex(events: fixture.events)
        let day = Fmt.dayKey(fixture.events[0].timestamp)
        let cases: [(String, String?, SourceKind?, EventKind?)] = [
            ("all", nil, nil, nil),
            ("day", day, nil, nil),
            ("source", nil, .codex, nil),
            ("kind", nil, nil, .gitCommit),
            ("day+source", day, .codex, nil),
            ("source+kind", nil, .claudeCode, .agentMessage)
        ]

        for (name, dayKey, source, kind) in cases {
            let projection = RouteProjectionBuilder.timeline(
                events: fixture.events,
                index: index,
                dayKey: dayKey,
                source: source,
                kind: kind
            )
            let reference = SyntheticAllRecordsProjection.baseline(
                events: fixture.events,
                dayKey: dayKey,
                source: source,
                kind: kind
            )
            try expectEqual(projection.filteredIndices.count, reference.filtered.count, "\(name) count")
            try expectEqual(projection.events(from: fixture.events).map(\.id), reference.filtered.map(\.id), "\(name) filtered IDs")
            try expectEqual(
                projection.groups.flatMap { $0.events(from: fixture.events).map(\.id) },
                reference.groups.flatMap { $0.events.map(\.id) },
                "\(name) grouped IDs"
            )
            try expectEqual(projection.dayKeys, reference.groups.map(\.dayKey), "\(name) group order")
        }
    }

    func todayProjectionComputesSessionAndHourDataOnce() throws {
        let fixture = SyntheticPerformanceFixture.make(count: 2_000)
        let index = EventProjectionIndex(events: fixture.events)
        let dayKey = Fmt.dayKey(fixture.anchor)
        let dayEvents = index.events(onDay: dayKey, from: fixture.events)
        let projection = RouteProjectionBuilder.today(
            dayKey: dayKey,
            events: dayEvents,
            report: fixture.reports.first { $0.day == dayKey },
            corrections: fixture.corrections
        )

        try expectEqual(projection.overview.eventCount, dayEvents.count)
        try expectEqual(projection.sessions.flatMap(\.events).count, dayEvents.count)
        try expectEqual(projection.hourLanes.reduce(0) { $0 + $1.marks.count }, dayEvents.count)
        try expectTrue(projection.sessions.allSatisfy { $0.events.prefix(EvidenceGroups.initialVisibleRowCount).count <= EvidenceGroups.initialVisibleRowCount })
        try expectTrue(projection.sessions.contains { $0.events.count > EvidenceGroups.initialVisibleRowCount }, "Show All remains required for large groups")
    }

    func weeklyProjectionCountsPreserveNavigationValues() throws {
        let fixture = SyntheticPerformanceFixture.make(count: 21)
        let projection = RouteProjectionBuilder.weekly(
            referenceDate: fixture.anchor,
            events: fixture.events,
            index: EventProjectionIndex(events: fixture.events)
        )
        let referenceCounts = projection.days.map { day in
            fixture.events.filter { Fmt.dayKey($0.timestamp) == Fmt.dayKey(day) }.count
        }
        try expectEqual(projection.counts, referenceCounts)
        try expectEqual(projection.total, referenceCounts.reduce(0, +))
        try expectEqual(projection.daysWithRecords, referenceCounts.filter { $0 > 0 }.count)
    }

    static var entries: [TestEntry] {
        let tests = RouteProjectionTests()
        return [
            TestEntry(suite: suiteName, name: "timelineFiltersAndGroupsMatchReferenceForAllCombinations") {
                try tests.timelineFiltersAndGroupsMatchReferenceForAllCombinations()
            },
            TestEntry(suite: suiteName, name: "todayProjectionComputesSessionAndHourDataOnce") {
                try tests.todayProjectionComputesSessionAndHourDataOnce()
            },
            TestEntry(suite: suiteName, name: "weeklyProjectionCountsPreserveNavigationValues") {
                try tests.weeklyProjectionCountsPreserveNavigationValues()
            }
        ]
    }
}
