import Foundation
@testable import ReflectLib

struct ReadingScreenTests {
    static let suiteName = "ReadingScreenTests"

    private func localDay(_ offsetFromToday: Int) -> Date {
        let start = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .day, value: offsetFromToday, to: start)!
    }

    // This Week's day rows map to exact Today dates.
    func weekDaysCoverAFullWeekAndRoundTrip() throws {
        let days = WeekCalendar.days(inWeekOf: Date())
        try expectEqual(days.count, 7, "a week has seven day rows")
        for day in days {
            let key = Fmt.dayKey(day)
            let parsed = try require(Fmt.date(fromDayKey: key), "week day key must parse back to a date")
            try expectEqual(Calendar.current.startOfDay(for: parsed), Calendar.current.startOfDay(for: day),
                            "opening the row must land on that exact local day")
        }
        // Days are consecutive.
        for (earlier, later) in zip(days, days.dropFirst()) {
            let difference = Calendar.current.dateComponents([.day], from: earlier, to: later).day ?? 99
            try expectEqual(difference, 1, "week days are consecutive")
        }
        let label = WeekCalendar.weekLabel(for: Date())
        try expectTrue(label.contains("–"), "week label shows a range: \(label)")
    }

    // Patterns stays score-free and never treats missing evidence as inactivity.
    func patternsReadingsStayHonestAboutMissingEvidence() throws {
        var events: [EvidenceEvent] = []
        for dayOffset in [-6, -5, -3, -1] {
            for index in 0..<3 {
                let start = Calendar.current.startOfDay(for: Date())
                let stamp = Calendar.current.date(byAdding: DateComponents(day: dayOffset, hour: 9 + index), to: start)!
                events.append(EvidenceEvent(
                    id: "pat-\(dayOffset)-\(index)",
                    sourceKind: .codex,
                    sourceName: "Codex CLI",
                    timestamp: stamp,
                    timestampApproximate: false,
                    kind: .userMessage,
                    summary: "Synthetic record",
                    detail: "",
                    evidencePath: "/tmp/reflect-fixture/pat.jsonl",
                    evidenceLine: 1,
                    observedAttribution: .unclear,
                    observedAttributionNote: "Structural role in transcript",
                    importedAt: stamp
                ))
            }
        }

        let summary = GrowthAnalyzer.summarize(events: events, corrections: [], today: Date())
        try expectFalse(summary.insufficientEvidence, "this fixture has enough evidence for patterns")
        // Zero-count weeks exist (weeks before first import) and stay in the data…
        try expectTrue(summary.weekly.contains { $0.eventCount == 0 }, "weeks without imports are present as zero counts")
        // …but no observation ever interprets them as inactivity or scores.
        for observation in summary.observations {
            let lowered = observation.text.lowercased()
            for banned in ["%", "score", "rank", "inactive", "unproductive", "nothing happened", "no work"] {
                try expectFalse(lowered.contains(banned), "observation must never claim \(banned): \(observation.text)")
            }
        }

        let sparse = GrowthAnalyzer.summarize(events: Fixtures.dayEvents(count: 2), corrections: [], today: Date())
        try expectTrue(sparse.insufficientEvidence)
        let reason = try require(sparse.reason)
        try expectTrue(reason.lowercased().contains("insufficient"), "sparse patterns state insufficiency openly")
        try expectTrue(reason.lowercased().contains("no score or rank"), "sparse patterns promise no score or rank")
    }

    static var entries: [TestEntry] {
        let tests = ReadingScreenTests()
        return [
            TestEntry(suite: suiteName, name: "weekDaysCoverAFullWeekAndRoundTrip") { try tests.weekDaysCoverAFullWeekAndRoundTrip() },
            TestEntry(suite: suiteName, name: "patternsReadingsStayHonestAboutMissingEvidence") { try tests.patternsReadingsStayHonestAboutMissingEvidence() }
        ]
    }
}
