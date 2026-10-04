import Foundation

struct TimelineGroupProjection: Identifiable, Equatable {
    let id: String
    let dayKey: String
    let indices: [Int]

    func events(from events: [EvidenceEvent]) -> [EvidenceEvent] {
        indices.compactMap { index in
            guard events.indices.contains(index) else { return nil }
            return events[index]
        }
    }
}

struct TimelineProjection: Equatable {
    let filteredIndices: [Int]
    let groups: [TimelineGroupProjection]

    var dayKeys: [String] { groups.map(\.dayKey) }

    func events(from events: [EvidenceEvent]) -> [EvidenceEvent] {
        filteredIndices.compactMap { index in
            guard events.indices.contains(index) else { return nil }
            return events[index]
        }
    }
}

struct LegacyNarrativeProjection: Equatable {
    let text: String
    let generatedAt: Date?
}

struct TodayRouteProjection {
    let events: [EvidenceEvent]
    let sortedEvents: [EvidenceEvent]
    let overview: DayOverview
    let sessions: [EvidenceGroup]
    let hourLanes: [(source: SourceKind, marks: [EvidenceHourMark])]
    let evidenceSubtitle: String
    let hasCommits: Bool
    let legacyNarrative: LegacyNarrativeProjection?
}

struct WeeklyRouteProjection: Equatable {
    let days: [Date]
    let counts: [Int]

    var total: Int { counts.reduce(0, +) }
    var daysWithRecords: Int { counts.filter { $0 > 0 }.count }
}

enum RouteProjectionBuilder {
    static func timeline(
        events: [EvidenceEvent],
        index: EventProjectionIndex,
        dayKey: String?,
        source: SourceKind?,
        kind: EventKind?
    ) -> TimelineProjection {
        let candidates = dayKey.map { index.indices(onDay: $0) } ?? Array(events.indices)
        var filteredIndices: [Int] = []
        filteredIndices.reserveCapacity(candidates.count)
        var grouped: [String: [Int]] = [:]

        for eventIndex in candidates {
            guard events.indices.contains(eventIndex) else { continue }
            let event = events[eventIndex]
            guard source == nil || event.sourceKind == source,
                  kind == nil || event.kind == kind else { continue }
            let eventDay = index.dayKey(atEventIndex: eventIndex) ?? Fmt.dayKey(event.timestamp)
            filteredIndices.append(eventIndex)
            grouped[eventDay, default: []].append(eventIndex)
        }

        let groups = grouped
            .map { dayKey, indices in
                TimelineGroupProjection(id: dayKey, dayKey: dayKey, indices: indices)
            }
            .sorted { $0.dayKey > $1.dayKey }
        return TimelineProjection(filteredIndices: filteredIndices, groups: groups)
    }

    static func today(
        dayKey: String,
        events: [EvidenceEvent],
        report: DailyReport?,
        corrections: [AttributionCorrection]
    ) -> TodayRouteProjection {
        let sortedEvents = events.sorted { $0.timestamp < $1.timestamp }
        let eventIDs = Set(events.map(\.id))
        let dayCorrections = corrections.filter { eventIDs.contains($0.eventId) }
        let overview = DayOverviewBuilder.overview(
            dayKey: dayKey,
            events: events,
            report: report,
            corrections: dayCorrections
        )
        let sessions = EvidenceGroups.sessions(for: sortedEvents)
        let hourLanes = EvidenceTimeline.lanes(for: events)
        let hasCommits = events.contains { $0.kind == .gitCommit || $0.sourceKind == .gitLocal }
        let sourceNames = Dictionary(grouping: events, by: \.sourceKind)
            .keys
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.displayName)
            .joined(separator: ", ")
        let evidenceSubtitle = events.isEmpty
            ? "No records are imported for this day"
            : "\(events.count) records from \(sourceNames), with times and details"
        let legacyNarrative: LegacyNarrativeProjection?
        if let report, !report.narrative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            legacyNarrative = LegacyNarrativeProjection(text: report.narrative, generatedAt: report.narrativeGeneratedAt)
        } else {
            legacyNarrative = nil
        }
        return TodayRouteProjection(
            events: events,
            sortedEvents: sortedEvents,
            overview: overview,
            sessions: sessions,
            hourLanes: hourLanes,
            evidenceSubtitle: evidenceSubtitle,
            hasCommits: hasCommits,
            legacyNarrative: legacyNarrative
        )
    }

    static func weekly(referenceDate: Date, events: [EvidenceEvent], index: EventProjectionIndex) -> WeeklyRouteProjection {
        let days = WeekCalendar.days(inWeekOf: referenceDate)
        let counts = days.map { index.count(onDay: Fmt.dayKey($0)) }
        return WeeklyRouteProjection(days: days, counts: counts)
    }
}
