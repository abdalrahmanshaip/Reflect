import Foundation

/// Qualitative growth output. Deliberately has no numeric score field.
public struct GrowthObservation: Identifiable, Hashable {
    public let id: String
    public let label: EvidenceLabel
    public let text: String

    public init(id: String, label: EvidenceLabel, text: String) {
        self.id = id
        self.label = label
        self.text = text
    }
}

public struct WeekTally: Identifiable, Hashable {
    public let id: String
    public let weekStart: Date
    public let eventCount: Int
    public let daysWithEvidence: Int
    public let bySource: [SourceKind: Int]

    public init(id: String, weekStart: Date, eventCount: Int, daysWithEvidence: Int, bySource: [SourceKind: Int]) {
        self.id = id
        self.weekStart = weekStart
        self.eventCount = eventCount
        self.daysWithEvidence = daysWithEvidence
        self.bySource = bySource
    }
}

public struct GrowthSummary: Hashable {
    public let insufficientEvidence: Bool
    public let reason: String?
    public let observations: [GrowthObservation]
    public let weekly: [WeekTally]
}
