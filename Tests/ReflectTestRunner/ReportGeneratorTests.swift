import Foundation
@testable import ReflectLib

struct ReportGeneratorTests {
    static let suiteName = "ReportGeneratorTests"
    private let dayKey = "2026-01-05"

    private func facts(count: Int, corrections: Int) -> DayFacts {
        DayFacts(dayKey: dayKey, events: Fixtures.dayEvents(count: count), correctionsApplied: corrections)
    }

    func sufficientEvidenceProducesDeterministicGroundedQuestions() throws {
        let draftA = ReportGenerator.draft(for: facts(count: 4, corrections: 1))
        let draftB = ReportGenerator.draft(for: facts(count: 4, corrections: 1))

        try expectFalse(draftA.insufficientEvidence)
        try expectNil(draftA.reason)
        try expectTrue(draftA.questions.count >= 1)

        try expectEqual(draftA.questions, draftB.questions, "questions must be deterministic")
        try expectEqual(draftA.narrative, draftB.narrative, "narrative draft must be deterministic")
        try expectEqual(draftA.questions.map(\.id), draftB.questions.map(\.id), "question ids must be stable")

        try expectTrue(draftA.questions[0].basis.contains("4"), "basis must ground the question in the record count")
        try expectFalse(draftA.questions[0].text.contains(where: \.isNumber), "primary question wording stays plain; counts live in the basis")
        try expectTrue(draftA.narrative.contains("4 events"))
        try expectTrue(draftA.narrative.contains("1"), "narrative must mention applied corrections")
    }

    func commitEvidenceAddsItsOwnQuestion() throws {
        var events = Fixtures.dayEvents(count: 4)
        events.append(EvidenceEvent(
            id: "fixture-commit-1",
            sourceKind: .gitLocal,
            sourceName: "Git (local repository)",
            timestamp: Fixtures.referenceDate,
            timestampApproximate: false,
            kind: .gitCommit,
            summary: "Commit 0a1b2c3: Fixture commit",
            detail: "",
            evidencePath: "/tmp/fixture-repo",
            evidenceLine: nil,
            observedAttribution: .unclear,
            observedAttributionNote: "Commit metadata only; do not infer human authorship.",
            importedAt: Fixtures.referenceDate
        ))

        let draft = ReportGenerator.draft(for: DayFacts(dayKey: dayKey, events: events, correctionsApplied: 0))
        try expectTrue(draft.questions.contains { $0.text.lowercased().contains("commit") })
    }

    func narrativeDistinguishesObservedFromInterpretation() throws {
        let draft = ReportGenerator.draft(for: facts(count: 5, corrections: 0))
        try expectTrue(draft.narrative.lowercased().contains("observed"))
        try expectTrue(draft.narrative.lowercased().contains("interpret"), "narrative should tell the user where interpretation belongs")
    }

    func coachingQuestionNamesTheSelectedDay() throws {
        let draft = ReportGenerator.draft(for: facts(count: 4, corrections: 0))
        try expectTrue(draft.questions[1].basis.contains(dayKey), "the basis must name the selected day")
    }

    static var entries: [TestEntry] {
        let tests = ReportGeneratorTests()
        return [
            TestEntry(suite: suiteName, name: "sufficientEvidenceProducesDeterministicGroundedQuestions") { try tests.sufficientEvidenceProducesDeterministicGroundedQuestions() },
            TestEntry(suite: suiteName, name: "commitEvidenceAddsItsOwnQuestion") { try tests.commitEvidenceAddsItsOwnQuestion() },
            TestEntry(suite: suiteName, name: "narrativeDistinguishesObservedFromInterpretation") { try tests.narrativeDistinguishesObservedFromInterpretation() },
            TestEntry(suite: suiteName, name: "coachingQuestionNamesTheSelectedDay") { try tests.coachingQuestionNamesTheSelectedDay() }
        ]
    }
}
