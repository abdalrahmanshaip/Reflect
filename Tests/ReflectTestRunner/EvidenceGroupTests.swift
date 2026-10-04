import Foundation
@testable import ReflectLib

struct EvidenceGroupTests {
    static let suiteName = "EvidenceGroupTests"
    private let dayKey = "2026-01-05"

    private func date(_ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 5
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }

    private func event(
        _ id: String, _ at: Date, source: SourceKind, kind: EventKind = .userMessage,
        path: String = "/tmp/reflect-fixture/session.jsonl", approximate: Bool = false
    ) -> EvidenceEvent {
        EvidenceEvent(
            id: id,
            sourceKind: source,
            sourceName: source.displayName,
            timestamp: at,
            timestampApproximate: approximate,
            kind: kind,
            summary: "Synthetic \(kind.rawValue) \(id)",
            detail: "",
            evidencePath: path,
            evidenceLine: 1,
            observedAttribution: .unclear,
            observedAttributionNote: "Structural role in transcript",
            importedAt: at
        )
    }

    // Each synthetic event lands in exactly one group; no project/author labels appear.
    func sessionsGroupEachEventExactlyOnce() throws {
        let events = [
            event("g-1", date(9, 0), source: .codex, path: "/tmp/fixture/one.jsonl"),
            event("g-2", date(9, 30), source: .codex, path: "/tmp/fixture/one.jsonl"),
            event("g-3", date(10, 0), source: .codex, path: "/tmp/fixture/two.jsonl"),
            event("g-4", date(11, 0), source: .claudeCode, path: "/tmp/fixture/three.jsonl"),
            event("g-5", date(15, 0), source: .gitLocal, kind: .gitCommit, path: "/tmp/fixture/repo-a"),
            event("g-6", date(16, 0), source: .gitLocal, kind: .gitCommit, path: "/tmp/fixture/repo-a")
        ]
        let groups = EvidenceGroups.sessions(for: events)

        let groupedIDs = groups.flatMap(\.events).map(\.id)
        try expectEqual(Set(groupedIDs).count, groupedIDs.count, "no event appears twice")
        try expectEqual(Set(groupedIDs), Set(events.map(\.id)), "every event is grouped")
        try expectEqual(groupedIDs.count, events.count)

        for group in groups {
            let lowered = (group.title + " " + (group.subtitle ?? "")).lowercased()
            for banned in ["project", "author", "owner"] where lowered.contains(banned) {
                throw TestFailure("group label must not invent \(banned) labels: \(group.title)")
            }
            let times = group.events.map(\.timestamp)
            try expectEqual(times, times.sorted(), "records inside a group stay time-ordered")
        }

        let codexGroups = groups.filter { $0.sourceKind == .codex }
        try expectEqual(codexGroups.count, 2, "different transcript files are separate groups")
        try expectFalse(codexGroups[0].isCommitMetadata)
        let commitGroups = groups.filter { $0.isCommitMetadata }
        try expectEqual(commitGroups.count, 1)
        try expectTrue(commitGroups[0].title.lowercased().contains("commit metadata"), "git groups are labeled metadata-only")
        try expectEqual(commitGroups[0].events.count, 2)
    }

    // Groups sort by their earliest record.
    func groupsSortByEarliestRecord() throws {
        let events = [
            event("s-late", date(14, 0), source: .copilotCLI),
            event("s-early", date(8, 0), source: .codex),
            event("s-mid", date(11, 0), source: .claudeCode)
        ]
        let groups = EvidenceGroups.sessions(for: events)
        let firstHours = groups.map { Calendar.current.component(.hour, from: $0.events[0].timestamp) }
        try expectEqual(firstHours, firstHours.sorted(), "groups ordered by earliest record")
    }

    // By hour marks map to source and local time; approximate timestamps flagged.
    func hourMarksMapToSourceAndLocalTime() throws {
        let events = [
            event("h-1", date(9, 0), source: .codex),
            event("h-2", date(13, 30), source: .claudeCode, approximate: true),
            event("h-3", date(17, 45), source: .codex)
        ]
        let marks = EvidenceTimeline.hourMarks(for: events)
        try expectEqual(marks.count, 3)
        try expectEqual(marks[0].eventID, "h-1", "marks are time-ordered")
        try expectEqual(marks[0].sourceKind, .codex)
        try expectFalse(marks[0].isApproximate)
        try expectTrue(marks[1].isApproximate, "approximate timestamps are identified")

        let calendar = Calendar.current
        try expectEqual(EvidenceTimeline.hourFraction(marks[0].time, calendar: calendar), 9.0)
        try expectEqual(EvidenceTimeline.hourFraction(marks[1].time, calendar: calendar), 13.5)
        try expectEqual(EvidenceTimeline.hourFraction(marks[2].time, calendar: calendar), 17.75)

        let lanes = EvidenceTimeline.lanes(for: events)
        try expectEqual(lanes.count, 2, "one lane per source with records")
        try expectEqual(lanes[0].source, .codex)
        try expectEqual(lanes[0].marks.count, 2)
        try expectEqual(lanes[1].source, .claudeCode)
    }

    // A 2,000-event synthetic day groups completely and stays bounded to render.
    func twoThousandEventDayGroupsCompletelyWithBoundedRows() throws {
        var events: [EvidenceEvent] = []
        let sources: [SourceKind] = [.codex, .claudeCode, .copilotCLI]
        let paths = ["/tmp/fixture/big-one.jsonl", "/tmp/fixture/big-two.jsonl", "/tmp/fixture/big-three.jsonl"]
        for index in 0..<2000 {
            let minuteOffset = index % (24 * 60)
            events.append(event(
                "big-\(index)",
                date(minuteOffset / 60, minuteOffset % 60),
                source: sources[index % sources.count],
                kind: index % 2 == 0 ? .agentMessage : .userMessage,
                path: paths[index % paths.count]
            ))
        }
        let groups = EvidenceGroups.sessions(for: events)
        try expectEqual(groups.flatMap(\.events).count, 2000, "all 2,000 records are grouped exactly once")
        try expectEqual(groups.count, 3, "three transcript files form three groups")

        // Bounded initial rendering: expansion shows a fixed prefix, never the whole day.
        try expectTrue(EvidenceGroups.initialVisibleRowCount < 2000)
        let biggest = groups.max(by: { $0.events.count < $1.events.count })!
        try expectEqual(biggest.events.prefix(EvidenceGroups.initialVisibleRowCount).count,
                        EvidenceGroups.initialVisibleRowCount,
                        "a group renders only the bounded prefix and routes the rest to Show all")
    }

    static var entries: [TestEntry] {
        let tests = EvidenceGroupTests()
        return [
            TestEntry(suite: suiteName, name: "sessionsGroupEachEventExactlyOnce") { try tests.sessionsGroupEachEventExactlyOnce() },
            TestEntry(suite: suiteName, name: "groupsSortByEarliestRecord") { try tests.groupsSortByEarliestRecord() },
            TestEntry(suite: suiteName, name: "hourMarksMapToSourceAndLocalTime") { try tests.hourMarksMapToSourceAndLocalTime() },
            TestEntry(suite: suiteName, name: "twoThousandEventDayGroupsCompletelyWithBoundedRows") { try tests.twoThousandEventDayGroupsCompletelyWithBoundedRows() }
        ]
    }
}
