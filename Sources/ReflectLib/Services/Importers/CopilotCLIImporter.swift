import Foundation

/// Adapter for Copilot CLI session-state event files (`events.jsonl`).
/// The exact event taxonomy is not publicly documented, so classification is
/// deliberately conservative: only clear user/agent/tool markers are imported,
/// and anything else is skipped. Verified against synthetic fixtures only.
struct CopilotCLIImporter: LineOrientedImporter {
    let sourceKind: SourceKind = .copilotCLI
    var sourceName: String { SourceKind.copilotCLI.displayName }

    func matches(fileName: String) -> Bool {
        fileName == "events.jsonl"
    }

    func parse(line: String) -> ImportedRecord? {
        guard let object = JSONParsing.object(line) else { return nil }
        let marker = (object["type"] as? String)
            ?? (object["role"] as? String)
            ?? (object["event"] as? String)
            ?? ""
        let lowered = marker.lowercased()
        guard !lowered.isEmpty else { return nil }

        let timestamp = TimestampParser.parse(object["timestamp"]) ?? TimestampParser.parse(object["ts"])

        if lowered.contains("user") {
            return ImportedRecord(
                timestamp: timestamp,
                kind: .userMessage,
                observedAttribution: .unclear,
                observedAttributionNote: "Observed '\(marker)' marker; not asserted as human authorship",
                summary: "User-role event",
                detail: JSONParsing.text(from: object["content"], limit: 400),
                recordType: "user"
            )
        }
        if lowered.contains("assistant") || lowered.contains("agent") {
            return ImportedRecord(
                timestamp: timestamp,
                kind: .agentMessage,
                observedAttribution: .agent,
                observedAttributionNote: "Observed '\(marker)' marker",
                summary: "Agent event",
                detail: JSONParsing.text(from: object["content"], limit: 400),
                recordType: "agent"
            )
        }
        if lowered.contains("tool") {
            return ImportedRecord(
                timestamp: timestamp,
                kind: .toolCall,
                observedAttribution: .agent,
                observedAttributionNote: "Tool event issued by the agent",
                summary: "Tool event",
                detail: "",
                recordType: "tool"
            )
        }
        return nil
    }
}
