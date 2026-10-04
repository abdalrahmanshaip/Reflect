import Foundation

/// Ephemeral projections over the in-memory event array. The index stores event
/// positions and local-day keys, not duplicate event payloads, so route changes
/// can reuse calendar work without changing the persisted JSON format.
public struct EventProjectionIndex {
    public let dayKeys: [String]

    private let indicesByDay: [String: [Int]]
    private let dayKeysByEventIndex: [String]

    public init(events: [EvidenceEvent], calendar: Calendar = .current) {
        var indicesByDay: [String: [Int]] = [:]
        var dayKeysByEventIndex: [String] = []
        dayKeysByEventIndex.reserveCapacity(events.count)

        for (index, event) in events.enumerated() {
            let dayKey = Fmt.dayKey(event.timestamp, calendar: calendar)
            dayKeysByEventIndex.append(dayKey)
            indicesByDay[dayKey, default: []].append(index)
        }

        self.indicesByDay = indicesByDay
        self.dayKeysByEventIndex = dayKeysByEventIndex
        self.dayKeys = indicesByDay.keys.sorted(by: >)
    }

    public func count(onDay dayKey: String) -> Int {
        indicesByDay[dayKey]?.count ?? 0
    }

    public func events(onDay dayKey: String, from events: [EvidenceEvent]) -> [EvidenceEvent] {
        (indicesByDay[dayKey] ?? []).compactMap { index in
            guard events.indices.contains(index) else { return nil }
            return events[index]
        }
    }

    func indices(onDay dayKey: String) -> [Int] {
        indicesByDay[dayKey] ?? []
    }

    func dayKey(atEventIndex index: Int) -> String? {
        guard dayKeysByEventIndex.indices.contains(index) else { return nil }
        return dayKeysByEventIndex[index]
    }
}
