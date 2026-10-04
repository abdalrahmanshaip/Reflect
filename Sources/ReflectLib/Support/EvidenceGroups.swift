import Foundation

/// A defensible session grouping of one day's evidence: records grouped by
/// source and transcript-file identity — the only session boundary the imported
/// data actually states. Git commits always form their own metadata-only group.
/// Project names and author labels are never invented here.
public struct EvidenceGroup: Identifiable, Equatable {
    public let id: String
    public let sourceKind: SourceKind
    public let title: String
    public let subtitle: String?
    public let isCommitMetadata: Bool
    public let events: [EvidenceEvent]
}

/// Pure grouping and by-hour projection used by the Today evidence inspector.
public enum EvidenceGroups {
    /// Records shown when a session group expands; the rest stays behind the
    /// explicit "Show all" route so huge days never render unbounded.
    public static let initialVisibleRowCount = 8

    /// Groups the day's events. Each event lands in exactly one group; groups
    /// sort by their earliest record.
    public static func sessions(for events: [EvidenceEvent]) -> [EvidenceGroup] {
        struct Bucket {
            let sourceKind: SourceKind
            let path: String
            let isCommit: Bool
            var events: [EvidenceEvent]
        }
        var byKey: [String: Bucket] = [:]
        for event in events {
            let isCommit = event.kind == .gitCommit || event.sourceKind == .gitLocal
            let key = "\(event.sourceKind.rawValue)|\(event.evidencePath)|\(isCommit ? "commit" : "records")"
            var bucket = byKey[key] ?? Bucket(sourceKind: event.sourceKind, path: event.evidencePath, isCommit: isCommit, events: [])
            bucket.events.append(event)
            byKey[key] = bucket
        }
        return byKey
            .map { key, bucket in
                let sorted = bucket.events.sorted { $0.timestamp < $1.timestamp }
                let baseName = bucket.sourceKind.displayName
                let title = bucket.isCommit ? "\(baseName) · commit metadata" : baseName
                let subtitle = shortPath(bucket.path)
                return EvidenceGroup(
                    id: key,
                    sourceKind: bucket.sourceKind,
                    title: title,
                    subtitle: subtitle,
                    isCommitMetadata: bucket.isCommit,
                    events: sorted
                )
            }
            .sorted { ($0.events.first?.timestamp ?? .distantPast) < ($1.events.first?.timestamp ?? .distantPast) }
    }

    /// Time range label for a group, e.g. "08:41–09:58" or "13:20 (approx.)".
    public static func timeRangeLabel(for events: [EvidenceEvent]) -> String {
        guard let first = events.first else { return "" }
        guard let last = events.last, first.timestamp != last.timestamp else {
            return Fmt.time(first.timestamp) + (first.timestampApproximate ? " ~" : "")
        }
        return "\(Fmt.time(first.timestamp))–\(Fmt.time(last.timestamp))"
    }

    private static func shortPath(_ path: String) -> String? {
        guard !path.isEmpty else { return nil }
        return (path as NSString).lastPathComponent
    }
}

/// One mark in the By hour lane: the record's actual local time and source.
public struct EvidenceHourMark: Identifiable, Equatable {
    public let eventID: String
    public let sourceKind: SourceKind
    public let time: Date
    public let isApproximate: Bool

    public var id: String { eventID }
}

public enum EvidenceTimeline {
    /// Marks for the By hour lanes, ordered by time.
    public static func hourMarks(for events: [EvidenceEvent]) -> [EvidenceHourMark] {
        events
            .map { EvidenceHourMark(eventID: $0.id, sourceKind: $0.sourceKind, time: $0.timestamp, isApproximate: $0.timestampApproximate) }
            .sorted { $0.time < $1.time }
    }

    /// The record's local time as a 0..<24 fraction of day, for lane positioning.
    public static func hourFraction(_ time: Date, calendar: Calendar = .current) -> Double {
        let components = calendar.dateComponents([.hour, .minute, .second], from: time)
        let hour = Double(components.hour ?? 0)
            + Double(components.minute ?? 0) / 60
            + Double(components.second ?? 0) / 3600
        return min(max(hour, 0), 24)
    }

    /// Lanes in a stable order: sources that have records that day, in SourceKind order.
    public static func lanes(for events: [EvidenceEvent]) -> [(source: SourceKind, marks: [EvidenceHourMark])] {
        let marks = hourMarks(for: events)
        return SourceKind.allCases.compactMap { kind in
            let kindMarks = marks.filter { $0.sourceKind == kind }
            guard !kindMarks.isEmpty else { return nil }
            return (kind, kindMarks)
        }
    }
}
