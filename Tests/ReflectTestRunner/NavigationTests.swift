import Foundation
@testable import ReflectLib

struct NavigationTests {
    static let suiteName = "NavigationTests"

    func dayKeyRoundTripsThroughRouteDate() throws {
        for key in ["2026-01-05", "2025-12-31", "2026-07-04", "2024-02-29"] {
            let date = try require(Fmt.date(fromDayKey: key), "day key must parse: \(key)")
            try expectEqual(Fmt.dayKey(date), key, "round trip must preserve the stored day key")
        }
        try expectNil(Fmt.date(fromDayKey: "not-a-day"), "garbage day keys must not parse")
    }

    func routesAreDistinctStableAndDayKeyed() throws {
        let dayKey = Fmt.dayKey(Fixtures.referenceDate)
        try expectEqual(ReflectRoute.day(dayKey: dayKey), ReflectRoute.day(dayKey: dayKey),
                        "the same day key selects the same route")
        try expectNotEqual(ReflectRoute.today, ReflectRoute.day(dayKey: dayKey),
                           "Today and an Earlier day are distinct routes even on the same date")
        try expectNotEqual(ReflectRoute.allRecords(dayKey: nil), ReflectRoute.allRecords(dayKey: dayKey),
                           "the inspector's day-filtered All Records route is distinct from the plain one")
        let all: Set<ReflectRoute> = [.today, .week, .patterns, .day(dayKey: dayKey), .allRecords(dayKey: nil), .allRecords(dayKey: dayKey), .sources]
        try expectEqual(all.count, 7, "all routes stay distinct for List selection")
    }

    func settingsCanBeSelectedAsASidebarDestination() throws {
        let dayKey = Fmt.dayKey(Fixtures.referenceDate)
        let routes: Set<ReflectRoute> = [
            .today, .week, .patterns, .day(dayKey: dayKey),
            .allRecords(dayKey: nil), .allRecords(dayKey: dayKey), .sources, .settings
        ]
        try expectEqual(routes.count, 8, "Settings is a stable destination alongside the existing routes")
        try expectTrue(routes.contains(.settings), "the Settings footer action has a selectable route")
    }

    func sidebarDayLabelsAreCompactAndSafe() throws {
        let label = Fmt.sidebarDayLabel("2026-01-05")
        try expectTrue(label.contains("Jan"), "label includes the month, got \(label)")
        try expectFalse(label.contains("2026"), "compact sidebar label omits the year, got \(label)")
        try expectEqual(Fmt.sidebarDayLabel("bogus"), "bogus", "unparseable keys fall back to themselves")
    }

    // Date labels are fixed English regardless of the Mac's system locale;
    // the formatters pin en_US_POSIX and these assertions fail if that pin
    // regresses on any non-English host.
    func dateLabelsStayEnglishForSyntheticDate() throws {
        let date = try require(Fmt.date(fromDayKey: "2026-01-05"), "synthetic day key must parse")
        try expectEqual(Fmt.weekdayName(for: date), "Monday",
                        "weekday names stay English for Monday, January 5, 2026")
        try expectEqual(Fmt.fullDate(date), "Monday, January 5, 2026",
                        "full dates stay English for the synthetic date")
        let stamped = try require(Calendar.current.date(bySettingHour: 9, minute: 41, second: 0, of: date),
                                  "synthetic timestamp must build in the local calendar")
        // Newer ICU renders AM/PM after a narrow no-break space even under
        // en_US_POSIX; normalize space variants so the assertion stays exact
        // about the visible English content.
        let dateTime = Fmt.dateTime(stamped).unicodeScalars.map { scalar in
            (scalar == "\u{202F}" || scalar == "\u{00A0}") ? " " : Character(scalar)
        }
        try expectEqual(String(dateTime), "Jan 5, 2026 at 9:41 AM",
                        "date/time labels stay English for the synthetic date")
        try expectEqual(Fmt.sidebarDayLabel("2026-01-05"), "Mon 5 Jan",
                        "compact sidebar labels stay in English day-month order")

        let label = WeekCalendar.weekLabel(for: date)
        try expectTrue(label.contains("–"), "week label shows a range: \(label)")
        let monthTokens = label.split(separator: " ")
            .filter { $0.contains(where: \.isLetter) }
            .map(String.init)
        let englishMonths: Set<String> = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                          "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        try expectFalse(monthTokens.isEmpty, "week label contains month tokens: \(label)")
        for month in monthTokens {
            try expectTrue(englishMonths.contains(month),
                           "week range months must be English abbreviations, got \(month) in \(label)")
        }
    }

    func recentProjectionForSidebarExcludesNothingByDefault() throws {
        // The sidebar filters today's row itself; the projection keeps every day.
        let day1 = try require(Fmt.date(fromDayKey: "2026-01-05"))
        let day2 = try require(Fmt.date(fromDayKey: "2026-01-04"))
        let events = Fixtures.dayEvents(count: 4, base: day1)
        let report = DailyReport(
            day: "2026-01-04",
            narrative: "",
            narrativeGeneratedAt: nil,
            answers: ["2026-01-04-q1": AnswerEntry(text: "Synthetic authored answer.", updatedAt: day2)],
            analysisResult: nil,
            analysisGeneratedAt: nil,
            updatedAt: day2
        )
        let recent = DayOverviewBuilder.recentDays(events: events, reports: [report], limit: 8)
        try expectEqual(recent.map(\.dayKey), ["2026-01-05", "2026-01-04"], "event day and report-only day both project")
        try expectTrue(recent[1].reflected, "nonblank answer shows as reflected in the sidebar row")
        try expectFalse(recent[0].reflected, "event-only day is not yet reflected")
    }

    static var entries: [TestEntry] {
        let tests = NavigationTests()
        return [
            TestEntry(suite: suiteName, name: "dayKeyRoundTripsThroughRouteDate") { try tests.dayKeyRoundTripsThroughRouteDate() },
            TestEntry(suite: suiteName, name: "routesAreDistinctStableAndDayKeyed") { try tests.routesAreDistinctStableAndDayKeyed() },
            TestEntry(suite: suiteName, name: "settingsCanBeSelectedAsASidebarDestination") { try tests.settingsCanBeSelectedAsASidebarDestination() },
            TestEntry(suite: suiteName, name: "sidebarDayLabelsAreCompactAndSafe") { try tests.sidebarDayLabelsAreCompactAndSafe() },
            TestEntry(suite: suiteName, name: "dateLabelsStayEnglishForSyntheticDate") { try tests.dateLabelsStayEnglishForSyntheticDate() },
            TestEntry(suite: suiteName, name: "recentProjectionForSidebarExcludesNothingByDefault") { try tests.recentProjectionForSidebarExcludesNothingByDefault() }
        ]
    }
}
