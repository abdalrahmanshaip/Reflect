import Foundation

/// Adapter for Claude Code project session JSONL files (`*.jsonl` under ~/.claude/projects).
/// Tolerant: unknown top-level types are skipped. Verified against synthetic fixtures only.
struct ClaudeCodeImporter: LineOrientedImporter {
    let sourceKind: SourceKind = .claudeCode
    var sourceName: String { SourceKind.claudeCode.displayName }

    func matches(fileName: String) -> Bool {
        fileName.hasSuffix(".jsonl")
    }

    func parse(line: String) -> ImportedRecord? {
        guard let object = JSONParsing.object(line) else { return nil }
        let type = object["type"] as? String ?? ""
        let timestamp = TimestampParser.parse(object["timestamp"])
        let message = object["message"] as? [String: Any]

        switch type {
        case "user":
            return ImportedRecord(
                timestamp: timestamp,
                kind: .userMessage,
                observedAttribution: .unclear,
                observedAttributionNote: "Observed type 'user' in transcript; may include tool-injected context, so this is not asserted as human authorship",
                summary: "User-role message",
                detail: JSONParsing.text(from: message?["content"], limit: 400),
                recordType: "user"
            )
        case "assistant":
            return ImportedRecord(
                timestamp: timestamp,
                kind: .agentMessage,
                observedAttribution: .agent,
                observedAttributionNote: "Observed type 'assistant' in transcript",
                summary: "Agent message",
                detail: JSONParsing.text(from: message?["content"], limit: 400),
                recordType: "assistant"
            )
        case "summary":
            let text = object["summary"] as? String ?? ""
            return ImportedRecord(
                timestamp: timestamp,
                kind: .summary,
                observedAttribution: .unclear,
                observedAttributionNote: "Session summary record",
                summary: "Session summary",
                detail: JSONParsing.cappedPreview(text, limit: 400),
                recordType: "summary"
            )
        case "system":
            let subtype = object["subtype"] as? String ?? "general"
            return ImportedRecord(
                timestamp: timestamp,
                kind: .systemEvent,
                observedAttribution: .unclear,
                observedAttributionNote: "CLI system record",
                summary: "System event (\(subtype))",
                detail: "",
                recordType: "system.\(subtype)"
            )
        default:
            return nil
        }
    }
}
