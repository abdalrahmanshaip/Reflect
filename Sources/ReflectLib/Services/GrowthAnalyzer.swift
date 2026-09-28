import Foundation

/// Cautious aggregate readings. Produces counts and clearly labeled inferences only —
/// no percentage scores, no competence ranks, and an explicit insufficient-evidence
/// state whenever the evidence base is too small.
enum GrowthAnalyzer {
    static func summarize(
        events: [EvidenceEvent],
        corrections: [AttributionCorrection],
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> GrowthSummary {
        let total = events.count
        let days = Set(events.map { Fmt.dayKey($0.timestamp, calendar: calendar) })

        guard total >= AppConstants.minimumEventsForGrowth,
              days.count >= AppConstants.minimumDistinctDaysForGrowth else {
            return GrowthSummary(
                insufficientEvidence: true,
                reason: "Insufficient evidence: \(total) event(s) across \(days.count) day(s). At least \(AppConstants.minimumEventsForGrowth) events across \(AppConstants.minimumDistinctDaysForGrowth) days are needed before any growth reading. No score or rank is produced.",
                observations: [],
                weekly: []
            )
        }

        let weekly = weekTallies(events: events, endingAt: today, calendar: calendar, weekCount: 8)

        var observations: [GrowthObservation] = []
        let bySource = Dictionary(grouping: events, by: \.sourceKind)
        let rankedSources = SourceKind.allCases
            .compactMap { kind -> (SourceKind, Int)? in
                guard let count = bySource[kind]?.count, count > 0 else { return nil }
                return (kind, count)
            }
            .sorted { $0.1 > $1.1 }

        if let top = rankedSources.first {
            observations.append(GrowthObservation(
                id: "obs-source-dominance",
                label: .observed,
                text: "Observed: \(top.0.displayName) accounts for \(top.1) of \(total) imported events."
            ))
        }

        let agentCount = events.filter { $0.observedAttribution == .agent }.count
        let unclearCount = events.filter { $0.observedAttribution == .unclear }.count
        let correctedToYou = corrections.filter { $0.attribution == .you }.count
        observations.append(GrowthObservation(
            id: "obs-attribution",
            label: .observed,
            text: "Observed: structural attribution across \(total) events is agent \(agentCount), unclear \(unclearCount), with \(correctedToYou) event(s) corrected by you."
        ))

        let approximateCount = events.filter(\.timestampApproximate).count
        if approximateCount > 0 {
            observations.append(GrowthObservation(
                id: "obs-approximate",
                label: .observed,
                text: "Observed: \(approximateCount) event(s) have approximate timestamps from file modification time."
            ))
        }

        if let top = rankedSources.first {
            observations.append(GrowthObservation(
                id: "inf-source-dominance",
                label: .inference,
                text: "App-generated inference: imported evidence is dominated by \(top.0.displayName). This reflects what was imported, not total effort, and may change as more sources are imported."
            ))
        }

        let sortedWeeks = weekly.filter { $0.eventCount > 0 }.sorted { $0.weekStart < $1.weekStart }
        if sortedWeeks.count >= 2 {
            let current = sortedWeeks[sortedWeeks.count - 1]
            let previous = sortedWeeks[sortedWeeks.count - 2]
            if current.eventCount >= 3, previous.eventCount >= 3 {
                let direction: String
                if current.eventCount > previous.eventCount { direction = "more" }
                else if current.eventCount < previous.eventCount { direction = "fewer" }
                else { direction = "about the same" }
                observations.append(GrowthObservation(
                    id: "inf-week-trend",
                    label: .inference,
                    text: "App-generated inference: the latest recorded week has \(direction) imported events than the previous one (\(current.eventCount) vs \(previous.eventCount)). Import coverage, not effort, may explain this."
                ))
            }
        }

        return GrowthSummary(insufficientEvidence: false, reason: nil, observations: observations, weekly: weekly)
    }

    static func weekTallies(
        events: [EvidenceEvent],
        endingAt today: Date,
        calendar: Calendar,
        weekCount: Int
    ) -> [WeekTally] {
        var tallies: [WeekTally] = []
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: today) else { return tallies }

        for offset in (0..<weekCount).reversed() {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeek.start),
                  let interval = calendar.dateInterval(of: .weekOfYear, for: weekStart) else { continue }
            let weekEvents = events.filter { interval.contains($0.timestamp) }
            let days = Set(weekEvents.map { Fmt.dayKey($0.timestamp, calendar: calendar) })
            let bySource = Dictionary(grouping: weekEvents, by: \.sourceKind).mapValues(\.count)
            tallies.append(WeekTally(
                id: Fmt.dayKey(interval.start),
                weekStart: interval.start,
                eventCount: weekEvents.count,
                daysWithEvidence: days.count,
                bySource: bySource
            ))
        }
        return tallies
    }
}
