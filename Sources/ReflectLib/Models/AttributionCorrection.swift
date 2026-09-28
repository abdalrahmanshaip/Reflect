import Foundation

/// The user's own attribution decision for an event. Stored separately from imported facts
/// so corrections survive re-imports and deletions.
public struct AttributionCorrection: Codable, Identifiable, Hashable {
    public var id: String { eventId }
    public let eventId: String
    public let attribution: Attribution
    public let updatedAt: Date

    public init(eventId: String, attribution: Attribution, updatedAt: Date) {
        self.eventId = eventId
        self.attribution = attribution
        self.updatedAt = updatedAt
    }
}

public enum AttributionResolver {
    /// Effective attribution: the user's correction wins; otherwise the observed structural value stands.
    public static func resolve(event: EvidenceEvent, corrections: [AttributionCorrection]) -> (value: Attribution, isCorrected: Bool) {
        if let correction = corrections.first(where: { $0.eventId == event.id }) {
            return (correction.attribution, true)
        }
        return (event.observedAttribution, false)
    }
}
