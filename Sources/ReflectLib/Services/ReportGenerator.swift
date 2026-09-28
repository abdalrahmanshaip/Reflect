import Foundation

struct DayFacts {
    let dayKey: String
    let events: [EvidenceEvent]
    let correctionsApplied: Int
}

struct CoachingQuestion: Identifiable, Hashable {
    let id: String
    let text: String
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
            text: "Evidence shows \(total) events from \(bySource.count) source(s) — \(sourceSummary). Which task took the most attention today, and what would you do differently next time?"
        ))
        questions.append(CoachingQuestion(
            id: "\(facts.dayKey)-q2",
            text: "Today's evidence structurally attributes \(agentCount) events to the agent and leaves \(unclearCount) unclear. Where was the key decision made — by you or by the tool — and what evidence tells you that?"
        ))
        if let commits = bySource[.gitLocal]?.count, commits > 0 {
            questions.append(CoachingQuestion(
                id: "\(facts.dayKey)-q3",
                text: "\(commits) commit(s) are recorded for this day (commit metadata only; authorship is not asserted). Which change would you defend in a code review, and why?"
            ))
        }

        return ReportDraft(narrative: narrative, questions: questions, insufficientEvidence: false, reason: nil)
    }
}
