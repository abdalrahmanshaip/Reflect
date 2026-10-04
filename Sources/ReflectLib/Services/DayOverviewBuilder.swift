import Foundation

/// Builds truthful day summaries for the redesigned surfaces. Deterministic:
/// same imported evidence and reports in, same overview out. The builder never
/// reads histories itself — callers pass already-imported events — and it never
/// infers project names, authorship, or skill that the evidence does not state.
public enum DayOverviewBuilder {

    /// A day counts as reflected only when a saved user answer has nonblank
    /// content. Generated narrative drafts and analysis results are never
    /// counted as the user's reflection.
    public static func isReflected(_ report: DailyReport?) -> Bool {
        guard let report else { return false }
        return report.answers.values.contains { entry in
            !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Builds the overview for one local day. Callers pass the day's events,
    /// the stored report if one exists, and the day's attribution corrections
    /// (with their values, so correction facts stay truthful about authorship).
    public static func overview(
        dayKey: String,
        events: [EvidenceEvent],
        report: DailyReport?,
        corrections: [AttributionCorrection]
    ) -> DayOverview {
        let reflected = isReflected(report)

        guard !events.isEmpty else {
            return DayOverview(
                dayKey: dayKey,
                hasEvidence: false,
                eventCount: 0,
                observedSentence: nil,
                facts: [],
                questions: [],
                statusNote: "No evidence is imported for \(dayKey). Reflect shows only what you explicitly import; nothing is imported automatically. You can still write your own reflection.",
                hasReport: report != nil,
                reflected: reflected
            )
        }

        let bySource = Dictionary(grouping: events, by: \.sourceKind)
        let sources = SourceKind.allCases.filter { (bySource[$0]?.count ?? 0) > 0 }
        let sourceNames = sources.map(\.displayName).joined(separator: ", ")

        var facts: [OverviewFact] = sources.map { kind in
            let sourceEvents = bySource[kind] ?? []
            let files = Set(sourceEvents.map(\.evidencePath)).count
            return OverviewFact(
                marker: .observed,
                text: "\(kind.displayName) · \(count(sourceEvents.count, unit: "record")) in \(count(files, unit: "file"))"
            )
        }

        let commitCount = events.filter { $0.kind == .gitCommit }.count
        if commitCount > 0 {
            facts.append(OverviewFact(
                marker: .observed,
                text: "\(count(commitCount, unit: "commit")) recorded (commit metadata only; authorship is not asserted)."
            ))
        }
        // Correction facts derive from the correction values so the text never
        // over-claims authorship: only corrections the user set to "You" mark
        // records as the user's own; other explicit corrections are described
        // as attribution changes. Corrections stay their own category, separate
        // from observed values.
        let correctionsByAttribution = Dictionary(grouping: corrections, by: \.attribution)
        for attribution in Attribution.allCases {
            guard let group = correctionsByAttribution[attribution], !group.isEmpty else { continue }
            let counted = count(group.count, unit: "record")
            switch attribution {
            case .you:
                facts.append(OverviewFact(
                    marker: .correction,
                    text: "You marked \(counted) as your own. Your corrections replace the observed labels."
                ))
            case .agent, .unclear:
                facts.append(OverviewFact(
                    marker: .correction,
                    text: "You changed \(counted) to the \(attribution.label) attribution. Your corrections replace the observed labels."
                ))
            }
        }
        let approximateCount = events.filter(\.timestampApproximate).count
        if approximateCount > 0 {
            facts.append(OverviewFact(
                marker: .observed,
                text: approximateCount == 1
                    ? "1 record has an approximate timestamp (taken from file modification time)."
                    : "\(approximateCount) records have approximate timestamps (taken from file modification time)."
            ))
        }

        let sentence = "Reflect found \(count(events.count, unit: "record")) for \(dayKey) across \(count(sources.count, unit: "source")): \(sourceNames)."

        var questions: [SuggestedQuestion] = []
        var statusNote: String?
        if events.count < AppConstants.minimumEventsForQuestion {
            statusNote = "\(count(events.count, unit: "record")) imported — at least \(AppConstants.minimumEventsForQuestion) are needed before Reflect suggests a question. You can still write your own reflection."
        } else {
            let draft = ReportGenerator.draft(
                for: DayFacts(dayKey: dayKey, events: events, correctionsApplied: corrections.count)
            )
            questions = draft.questions.map { SuggestedQuestion(id: $0.id, text: $0.text, basis: $0.basis) }
        }

        return DayOverview(
            dayKey: dayKey,
            hasEvidence: true,
            eventCount: events.count,
            observedSentence: sentence,
            facts: facts,
            questions: questions,
            statusNote: statusNote,
            hasReport: report != nil,
            reflected: reflected
        )
    }

    /// Recent sidebar days: every day with imported events plus every day with a
    /// saved report (report-only days included), newest local day first.
    public static func recentDays(
        events: [EvidenceEvent],
        reports: [DailyReport],
        limit: Int = 8
    ) -> [RecentDay] {
        recentDays(index: EventProjectionIndex(events: events), reports: reports, limit: limit)
    }

    /// Recent sidebar days using an already-built event index. Report-only
    /// days remain in the union and are never treated as imported evidence.
    public static func recentDays(
        index: EventProjectionIndex,
        reports: [DailyReport],
        limit: Int = 8
    ) -> [RecentDay] {
        let reportsByDay = Dictionary(reports.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        var dayKeys = Set(index.dayKeys)
        dayKeys.formUnion(reportsByDay.keys)
        return dayKeys
            .sorted(by: >)
            .prefix(limit)
            .map { day in
                let report = reportsByDay[day]
                return RecentDay(
                    dayKey: day,
                    eventCount: index.count(onDay: day),
                    hasReport: report != nil,
                    reflected: isReflected(report)
                )
            }
    }

    private static func count(_ n: Int, unit: String) -> String {
        n == 1 ? "1 \(unit)" : "\(n) \(unit)s"
    }
}
