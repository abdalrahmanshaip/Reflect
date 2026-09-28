import Foundation

/// Idempotent merge of imported events. Re-importing the same evidence adds nothing,
/// because identity is derived from stable source keys rather than import order.
enum EventDeduplicator {
    static func merge(existing: [EvidenceEvent], incoming: [EvidenceEvent]) -> (merged: [EvidenceEvent], added: Int) {
        var seen = Set(existing.map(\.id))
        var merged = existing
        var added = 0
        for event in incoming where !seen.contains(event.id) {
            seen.insert(event.id)
            merged.append(event)
            added += 1
        }
        return (merged, added)
    }
}
