import Foundation
@testable import ReflectLib

struct LocalDayTests {
    static let suiteName = "LocalDayTests"

    // MARK: Synthetic helpers (never real activity)

    /// Deterministic UTC calendar, independent of the machine's current time zone.
    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Builds an instant from UTC components so the machine time zone is irrelevant.
    private func utcInstant(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return utcCalendar().date(from: components)!
    }

    private func gregorian() -> Calendar {
        Calendar(identifier: .gregorian)
    }

    // MARK: Time zone identity

    func timezoneChangeProducesDistinctIdentitiesForOneInstant() throws {
        let instant = utcInstant(2026, 1, 15, 0, 30) // 2026-01-15T00:30:00Z
        let tokyo = try require(TimeZone(identifier: "Asia/Tokyo"), "missing synthetic time zone Asia/Tokyo")
        let newYork = try require(TimeZone(identifier: "America/New_York"), "missing synthetic time zone America/New_York")

        let tokyoDay = LocalDay(instant: instant, calendar: gregorian(), timeZone: tokyo)
        let newYorkDay = LocalDay(instant: instant, calendar: gregorian(), timeZone: newYork)

        try expectEqual(tokyoDay.year, 2026)
        try expectEqual(tokyoDay.month, 1)
        try expectEqual(tokyoDay.day, 15)
        try expectEqual(newYorkDay.year, 2026)
        try expectEqual(newYorkDay.month, 1)
        try expectEqual(newYorkDay.day, 14)
        try expectNotEqual(tokyoDay, newYorkDay, "one instant must yield distinct identities under different time zones")
        try expectEqual(tokyoDay.timeZoneIdentifier, "Asia/Tokyo")
        try expectEqual(newYorkDay.timeZoneIdentifier, "America/New_York")
        try expectEqual(tokyoDay.calendarIdentifier, "gregorian")
    }

    // MARK: DST transition

    func dstTransitionUsesExplicitCalendarAndTimeZone() throws {
        let timeZone = try require(TimeZone(identifier: "America/New_York"), "missing synthetic time zone America/New_York")
        // US spring-forward 2026-03-08 02:00 EST -> 03:00 EDT. Local midnight of
        // Mar 8 falls at 05:00:00Z, so instants one second apart span two civil days.
        let beforeMidnight = utcInstant(2026, 3, 8, 4, 59, 59)
        let atMidnight = utcInstant(2026, 3, 8, 5, 0, 0)

        let dayBefore = LocalDay(instant: beforeMidnight, calendar: gregorian(), timeZone: timeZone)
        let dayOf = LocalDay(instant: atMidnight, calendar: gregorian(), timeZone: timeZone)

        try expectEqual(dayBefore.year, 2026)
        try expectEqual(dayBefore.month, 3)
        try expectEqual(dayBefore.day, 7)
        try expectEqual(dayOf.year, 2026)
        try expectEqual(dayOf.month, 3)
        try expectEqual(dayOf.day, 8)
        try expectNotEqual(dayBefore, dayOf, "DST-shifted local midnight must split consecutive civil days")
        try expectEqual(dayOf.timeZoneIdentifier, "America/New_York")
    }

    /// The real spring-forward jump: 2026-03-08T06:59:59Z is 01:59:59 EST and
    /// 2026-03-08T07:00:00Z is 03:00:00 EDT (local hour 1 -> 3, 02:xx never
    /// exists). Both instants belong to the same civil day under the supplied
    /// calendar/time zone.
    func springForwardGapMapsBothInstantsToSameLocalDay() throws {
        let timeZone = try require(TimeZone(identifier: "America/New_York"), "missing synthetic time zone America/New_York")
        var calendar = gregorian()
        calendar.timeZone = timeZone

        let beforeJump = utcInstant(2026, 3, 8, 6, 59, 59)
        let afterJump = utcInstant(2026, 3, 8, 7, 0, 0)

        let dayBeforeJump = LocalDay(instant: beforeJump, calendar: gregorian(), timeZone: timeZone)
        let dayAfterJump = LocalDay(instant: afterJump, calendar: gregorian(), timeZone: timeZone)

        try expectEqual(dayBeforeJump.year, 2026)
        try expectEqual(dayBeforeJump.month, 3)
        try expectEqual(dayBeforeJump.day, 8)
        try expectEqual(dayAfterJump.year, 2026)
        try expectEqual(dayAfterJump.month, 3)
        try expectEqual(dayAfterJump.day, 8)
        try expectEqual(dayBeforeJump, dayAfterJump, "both sides of the spring-forward jump are the same civil day")

        let hourBefore = calendar.component(.hour, from: beforeJump)
        let hourAfter = calendar.component(.hour, from: afterJump)
        try expectEqual(hourBefore, 1)
        try expectEqual(hourAfter, 3, "local wall-clock hour must jump 1 -> 3 across the gap")
        try expectEqual(dayAfterJump.timeZoneIdentifier, "America/New_York")
    }

    // MARK: Codable round trip

    func codableRoundTripPreservesExactIdentity() throws {
        let original = LocalDay(
            calendarIdentifier: "gregorian",
            timeZoneIdentifier: "Pacific/Chatham",
            year: 2026,
            month: 7,
            day: 31
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LocalDay.self, from: data)

        try expectEqual(decoded.calendarIdentifier, original.calendarIdentifier)
        try expectEqual(decoded.timeZoneIdentifier, original.timeZoneIdentifier)
        try expectEqual(decoded.year, original.year)
        try expectEqual(decoded.month, original.month)
        try expectEqual(decoded.day, original.day)
        try expectEqual(decoded, original, "round trip must preserve full identity")
        try expectEqual(decoded.hashValue, original.hashValue, "round trip must preserve hashability identity")
    }
}

extension LocalDayTests {
    static var entries: [TestEntry] {
        let tests = LocalDayTests()
        return [
            TestEntry(suite: suiteName, name: "timezoneChangeProducesDistinctIdentitiesForOneInstant") {
                try tests.timezoneChangeProducesDistinctIdentitiesForOneInstant()
            },
            TestEntry(suite: suiteName, name: "dstTransitionUsesExplicitCalendarAndTimeZone") {
                try tests.dstTransitionUsesExplicitCalendarAndTimeZone()
            },
            TestEntry(suite: suiteName, name: "springForwardGapMapsBothInstantsToSameLocalDay") {
                try tests.springForwardGapMapsBothInstantsToSameLocalDay()
            },
            TestEntry(suite: suiteName, name: "codableRoundTripPreservesExactIdentity") {
                try tests.codableRoundTripPreservesExactIdentity()
            }
        ]
    }
}
