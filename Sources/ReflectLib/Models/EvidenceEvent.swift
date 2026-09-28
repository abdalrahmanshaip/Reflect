import Foundation

/// A single imported piece of evidence. Content previews stay small and local.
public struct EvidenceEvent: Codable, Identifiable, Hashable {
    public let id: String
    public let sourceKind: SourceKind
    public let sourceName: String
    public let timestamp: Date
    public let timestampApproximate: Bool
    public let kind: EventKind
    public let summary: String
    public let detail: String
    public let evidencePath: String
    public let evidenceLine: Int?
    public let observedAttribution: Attribution
    public let observedAttributionNote: String
    public let importedAt: Date

    public init(
        id: String,
        sourceKind: SourceKind,
        sourceName: String,
        timestamp: Date,
        timestampApproximate: Bool,
        kind: EventKind,
        summary: String,
        detail: String,
        evidencePath: String,
        evidenceLine: Int?,
        observedAttribution: Attribution,
        observedAttributionNote: String,
        importedAt: Date
    ) {
        self.id = id
        self.sourceKind = sourceKind
        self.sourceName = sourceName
        self.timestamp = timestamp
        self.timestampApproximate = timestampApproximate
        self.kind = kind
        self.summary = summary
        self.detail = detail
        self.evidencePath = evidencePath
        self.evidenceLine = evidenceLine
        self.observedAttribution = observedAttribution
        self.observedAttributionNote = observedAttributionNote
        self.importedAt = importedAt
    }
}

public enum EventKind: String, Codable, CaseIterable, Hashable {
    case sessionStart = "session_start"
    case userMessage = "user_message"
    case agentMessage = "agent_message"
    case toolCall = "tool_call"
    case toolOutput = "tool_output"
    case reasoning
    case summary
    case systemEvent = "system"
    case gitCommit = "git_commit"
    case other

    public var label: String {
        switch self {
        case .sessionStart: return "Session start"
        case .userMessage: return "User message"
        case .agentMessage: return "Agent message"
        case .toolCall: return "Tool call"
        case .toolOutput: return "Tool output"
        case .reasoning: return "Reasoning"
        case .summary: return "Summary"
        case .systemEvent: return "System"
        case .gitCommit: return "Commit"
        case .other: return "Event"
        }
    }

    public var symbolName: String {
        switch self {
        case .sessionStart: return "play.circle"
        case .userMessage: return "person.text.rectangle"
        case .agentMessage: return "sparkles.rectangle.stack"
        case .toolCall: return "wrench.and.screwdriver"
        case .toolOutput: return "tray.full"
        case .reasoning: return "brain"
        case .summary: return "doc.plaintext"
        case .systemEvent: return "gearshape"
        case .gitCommit: return "smallcircle.filled.circle"
        case .other: return "circle.dashed"
        }
    }
}
