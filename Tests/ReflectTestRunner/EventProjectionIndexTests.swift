import Foundation
@testable import ReflectLib

struct EventProjectionIndexTests {
    static let suiteName = "EventProjectionIndexTests"

    func emptyAndSingleDayFixturesMatchReferenceCounts() throws {
        let empty = EventProjectionIndex(events: [])
        try expectTrue(empty.dayKeys.isEmpty)
        try expectEqual(empty.count(onDay: "2026-01-05"), 0)

        let events = Fixtures.dayEvents(count: 7)
        let index = EventProjectionIndex(events: events)
        let key = Fmt.dayKey(events[0].timestamp)
        try expectEqual(index.count(onDay: key), 7)
        try expectEqual(index.events(onDay: key, from: events), events)
        try expectEqual(index.dayKeys, [key])
    }

    func multiWeekAndMidnightFixturesPreserveLocalDays() throws {
        let calendar = Calendar.current
        let first = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: Fixtures.referenceDate)!
        let second = calendar.date(byAdding: .minute, value: 2, to: calendar.startOfDay(for: Fixtures.referenceDate))!
        let events = Fixtures.dayEvents(count: 10, base: first) + Fixtures.dayEvents(count: 3, base: second)
        let index = EventProjectionIndex(events: events)
        let reference = Dictionary(grouping: events) { Fmt.dayKey($0.timestamp) }

        try expectEqual(Set(index.dayKeys), Set(reference.keys))
        for (key, values) in reference {
            try expectEqual(index.count(onDay: key), values.count, "count parity for \(key)")
            try expectEqual(index.events(onDay: key, from: events).map(\.id), values.map(\.id), "event order parity for \(key)")
        }
    }

    func weeklyTalliesMatchReferenceSinglePassOutput() throws {
        let fixture = SyntheticPerformanceFixture.make(count: 2_000)
        let index = EventProjectionIndex(events: fixture.events)
        let indexed = GrowthAnalyzer.weekTallies(
            events: fixture.events,
            endingAt: fixture.anchor,
            calendar: .current,
            weekCount: 8,
            index: index
        )
        let reference = referenceWeekTallies(
            events: fixture.events,
            endingAt: fixture.anchor,
            calendar: .current,
            weekCount: 8
        )
        try expectEqual(indexed, reference, "indexed weekly counts preserve reference output")
    }

    func reportOnlyDaysRemainInRecentProjection() throws {
        let fixture = SyntheticPerformanceFixture.make(count: 3)
        let index = EventProjectionIndex(events: fixture.events)
        let recent = DayOverviewBuilder.recentDays(index: index, reports: fixture.reports, limit: 8)
        try expectTrue(recent.contains { $0.eventCount == 0 && $0.hasReport }, "report-only day remains visible")
        try expectTrue(recent.contains { $0.reflected }, "nonblank authored answer remains reflected")
    }

    func correctionsStaySeparateFromEventIndex() throws {
        let fixture = SyntheticPerformanceFixture.make(count: 21)
        let index = EventProjectionIndex(events: fixture.events)
        let corrected = fixture.corrections[0]
        let key = Fmt.dayKey(fixture.events.first { $0.id == corrected.eventId }!.timestamp)
        try expectEqual(index.count(onDay: key), fixture.events.filter { Fmt.dayKey($0.timestamp) == key }.count)
        try expectEqual(index.dayKeys, EventProjectionIndex(events: fixture.events).dayKeys, "corrections do not mutate index state")
    }

    private func referenceWeekTallies(
        events: [EvidenceEvent],
        endingAt today: Date,
        calendar: Calendar,
        weekCount: Int
    ) -> [WeekTally] {
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: today) else { return [] }
        return (0..<weekCount).reversed().compactMap { offset in
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeek.start),
                  let interval = calendar.dateInterval(of: .weekOfYear, for: weekStart) else { return nil }
            let weekEvents = events.filter { interval.contains($0.timestamp) }
            let days = Set(weekEvents.map { Fmt.dayKey($0.timestamp, calendar: calendar) })
            let bySource = Dictionary(grouping: weekEvents, by: \.sourceKind).mapValues(\.count)
            return WeekTally(
                id: Fmt.dayKey(interval.start),
                weekStart: interval.start,
                eventCount: weekEvents.count,
                daysWithEvidence: days.count,
                bySource: bySource
            )
        }
    }

    static var entries: [TestEntry] {
        let tests = EventProjectionIndexTests()
        return [
            TestEntry(suite: suiteName, name: "emptyAndSingleDayFixturesMatchReferenceCounts") {
                try tests.emptyAndSingleDayFixturesMatchReferenceCounts()
            },
            TestEntry(suite: suiteName, name: "multiWeekAndMidnightFixturesPreserveLocalDays") {
                try tests.multiWeekAndMidnightFixturesPreserveLocalDays()
            },
            TestEntry(suite: suiteName, name: "weeklyTalliesMatchReferenceSinglePassOutput") {
                try tests.weeklyTalliesMatchReferenceSinglePassOutput()
            },
            TestEntry(suite: suiteName, name: "reportOnlyDaysRemainInRecentProjection") {
                try tests.reportOnlyDaysRemainInRecentProjection()
            },
            TestEntry(suite: suiteName, name: "correctionsStaySeparateFromEventIndex") {
                try tests.correctionsStaySeparateFromEventIndex()
            }
        ]
    }
}
