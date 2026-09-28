import Foundation
@testable import ReflectLib

struct InsufficientEvidenceTests {
    static let suiteName = "InsufficientEvidenceTests"

    func dailyDraftWithFewEventsStatesInsufficientEvidence() throws {
        let events = Fixtures.dayEvents(count: 2)
        let draft = ReportGenerator.draft(for: DayFacts(dayKey: "2026-01-05", events: events, correctionsApplied: 0))
        try expectTrue(draft.insufficientEvidence)
        try expectTrue(draft.questions.isEmpty, "no coaching question without enough evidence")
        try expectTrue(draft.reason?.contains("Insufficient") == true)
    }

    func noPercentScoresAnywhereInDraft() throws {
        let events = Fixtures.dayEvents(count: 2)
        let draft = ReportGenerator.draft(for: DayFacts(dayKey: "2026-01-05", events: events, correctionsApplied: 0))
        try expectFalse(draft.narrative.contains("%"))
        for question in draft.questions {
            try expectFalse(question.text.contains("%"))
        }
    }

    func growthWithLittleEvidenceStatesInsufficientEvidence() throws {
        let events = Fixtures.dayEvents(count: 5)
        let summary = GrowthAnalyzer.summarize(events: events, corrections: [], today: Fixtures.referenceDate)
        try expectTrue(summary.insufficientEvidence)
        try expectTrue(summary.observations.isEmpty, "no growth observations without enough evidence")
        try expectTrue(summary.reason?.contains("Insufficient") == true)
    }

    func growthNeverProducesPercentScores() throws {
        let events = Fixtures.dayEvents(count: 2)
        let summary = GrowthAnalyzer.summarize(events: events, corrections: [], today: Fixtures.referenceDate)
        try expectTrue(summary.reason?.contains("%") != true)
        for observation in summary.observations {
            try expectFalse(observation.text.contains("%"))
        }
    }

    static var entries: [TestEntry] {
        let tests = InsufficientEvidenceTests()
        return [
            TestEntry(suite: suiteName, name: "dailyDraftWithFewEventsStatesInsufficientEvidence") { try tests.dailyDraftWithFewEventsStatesInsufficientEvidence() },
            TestEntry(suite: suiteName, name: "noPercentScoresAnywhereInDraft") { try tests.noPercentScoresAnywhereInDraft() },
            TestEntry(suite: suiteName, name: "growthWithLittleEvidenceStatesInsufficientEvidence") { try tests.growthWithLittleEvidenceStatesInsufficientEvidence() },
            TestEntry(suite: suiteName, name: "growthNeverProducesPercentScores") { try tests.growthNeverProducesPercentScores() }
        ]
    }
}
