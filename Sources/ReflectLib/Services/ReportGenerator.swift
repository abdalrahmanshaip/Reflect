import Foundation

struct DayFacts {
    let dayKey: String
    let events: [EvidenceEvent]
    let correctionsApplied: Int
}

struct CoachingQuestion: Identifiable, Hashable {
    let id: String
    let text: String
    /// Names the records the question came from. Shown under the question so the
    /// question itself can stay plain instead of restating counts like a score.
    let basis: String
}

struct ReportDraft {
    let narrative: String
    let questions: [CoachingQuestion]
    let insufficientEvidence: Bool
    let reason: String?
}

/// Deterministic daily drafts. Same facts in, same draft out — no randomness, no AI,
/// and no claims beyond what the evidence shows.
enum ReportGenerator {
    static func draft(for facts: DayFacts) -> ReportDraft {
        let total = facts.events.count
        let minimum = AppConstants.minimumEventsForQuestion

        guard total >= minimum else {
            return ReportDraft(
                narrative: "Insufficient evidence for \(facts.dayKey): \(total) event(s) imported, fewer than \(minimum). Observed evidence (if any) is listed under Timeline. No questions or interpretations are generated, to avoid unfounded prompts.",
                questions: [],
                insufficientEvidence: true,
                reason: "Insufficient evidence for \(facts.dayKey): \(total) event(s); at least \(minimum) events are needed before a coaching question is offered."
            )
        }

        let bySource = Dictionary(grouping: facts.events, by: \.sourceKind)
        let sourceSummary = SourceKind.allCases.compactMap { kind -> String? in
            guard let count = bySource[kind]?.count, count > 0 else { return nil }
            return "\(kind.displayName): \(count)"
        }.joined(separator: ", ")

        let byKind = Dictionary(grouping: facts.events, by: \.kind)
        let kindSummary = byKind
            .map { "\($0.key.label): \($0.value.count)" }
            .sorted()
            .joined(separator: ", ")

        let agentCount = facts.events.filter { $0.observedAttribution == .agent }.count
        let unclearCount = facts.events.filter { $0.observedAttribution == .unclear }.count
        let youCount = facts.events.filter { $0.observedAttribution == .you }.count
        let approximateCount = facts.events.filter(\.timestampApproximate).count

        let lines = [
            "Observed facts for \(facts.dayKey) (generated draft; edit freely):",
            "- \(total) events imported from \(bySource.count) source(s): \(sourceSummary).",
            "- Event types: \(kindSummary).",
            "- Structural attribution (observed roles only, not authorship): agent \(agentCount), unclear \(unclearCount), you \(youCount).",
            "- Your attribution corrections applied: \(facts.correctionsApplied).",
            approximateCount > 0
                ? "- \(approximateCount) event(s) have approximate timestamps (taken from file modification time)."
                : "- All events have explicit timestamps.",
            "This draft records only observed facts from imported evidence. Interpretations, context, and opinions belong in your edits and in the answers below."
        ]
        let narrative = lines.joined(separator: "\n")

        var questions: [CoachingQuestion] = []
        questions.append(CoachingQuestion(
            id: "\(facts.dayKey)-q1",
            text: "Which task took the most attention, and what would you do differently next time?",
            basis: "Based on \(total) record(s) from \(bySource.count) source(s): \(sourceSummary)."
        ))
        questions.append(CoachingQuestion(
            id: "\(facts.dayKey)-q2",
            text: "When a tool suggested something, how did you decide whether to take it — and is there a call you would make differently now?",
            basis: "Based on records in \(facts.dayKey) recorded with the agent role (\(agentCount)) or left unclear (\(unclearCount)); observed roles, not authorship."
        ))
        if let commits = bySource[.gitLocal]?.count, commits > 0 {
            questions.append(CoachingQuestion(
                id: "\(facts.dayKey)-q3",
                text: "Some commits are recorded for this day: which change would you defend in a code review, and why?",
                basis: "Based on \(commits) commit(s) (commit metadata only; authorship is not asserted)."
            ))
        }

        return ReportDraft(narrative: narrative, questions: questions, insufficientEvidence: false, reason: nil)
    }
}
