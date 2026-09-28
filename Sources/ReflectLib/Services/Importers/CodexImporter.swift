import Foundation

/// Adapter for Codex CLI rollout JSONL files (`rollout-*.jsonl`).
///
/// Parsing is intentionally tolerant and verified only against synthetic fixtures:
/// unknown top-level or payload types are skipped rather than guessed.
/// "user"-role transcript lines are attributed `unclear` because such lines can
/// also carry tool-injected context; corrections stay in the user's hands.
struct CodexImporter: LineOrientedImporter {
    let sourceKind: SourceKind = .codex
    var sourceName: String { SourceKind.codex.displayName }

    func matches(fileName: String) -> Bool {
        fileName.hasPrefix("rollout-") && fileName.hasSuffix(".jsonl")
    }

    func parse(line: String) -> ImportedRecord? {
        guard let object = JSONParsing.object(line) else { return nil }
        let type = object["type"] as? String ?? ""
        let payload = object["payload"] as? [String: Any]
        let timestamp = TimestampParser.parse(object["timestamp"])

        switch type {
        case "session_meta":
            let sessionID = payload?["id"] as? String
            let summary = sessionID.map { "Codex session started (\($0.prefix(16)))" } ?? "Codex session started"
            return ImportedRecord(
                timestamp: timestamp,
                kind: .sessionStart,
                observedAttribution: .unclear,
                observedAttributionNote: "Session metadata; no authorship implied",
                summary: summary,
                detail: "",
                recordType: "session_meta"
            )
        case "response_item":
            guard let payload else { return nil }
            return record(fromPayload: payload, timestamp: timestamp)
        case "event_msg":
            let eventType = payload?["type"] as? String ?? "unknown"
            return ImportedRecord(
                timestamp: timestamp,
                kind: .other,
                observedAttribution: .unclear,
                observedAttributionNote: "CLI event; no authorship implied",
                summary: "Codex event: \(eventType)",
                detail: "",
                recordType: "event_msg:\(eventType)"
            )
        default:
            return nil
        }
    }

    private func record(fromPayload payload: [String: Any], timestamp: Date?) -> ImportedRecord? {
        let payloadType = payload["type"] as? String ?? ""

        switch payloadType {
        case "message":
            let role = payload["role"] as? String ?? "unknown"
            switch role {
            case "assistant":
                return ImportedRecord(
                    timestamp: timestamp,
                    kind: .agentMessage,
                    observedAttribution: .agent,
                    observedAttributionNote: "Observed role 'assistant' in transcript",
                    summary: "Agent message",
                    detail: JSONParsing.text(from: payload["content"], limit: 400),
                    recordType: "message.assistant"
                )
            case "user":
                return ImportedRecord(
                    timestamp: timestamp,
                    kind: .userMessage,
                    observedAttribution: .unclear,
                    observedAttributionNote: "Observed role 'user' in transcript; may include tool-injected context, so this is not asserted as human authorship",
                    summary: "User-role message",
                    detail: JSONParsing.text(from: payload["content"], limit: 400),
                    recordType: "message.user"
                )
            default:
                return ImportedRecord(
                    timestamp: timestamp,
                    kind: .other,
                    observedAttribution: .unclear,
                    observedAttributionNote: "Observed role '\(role)' in transcript",
                    summary: "Message with role '\(role)'",
                    detail: "",
                    recordType: "message.\(role)"
                )
            }
        case "reasoning", "agent_reasoning":
            return ImportedRecord(
                timestamp: timestamp,
                kind: .reasoning,
                observedAttribution: .agent,
                observedAttributionNote: "Model reasoning step",
                summary: "Reasoning step",
                detail: "",
                recordType: "reasoning"
            )
        case "function_call", "local_shell_call", "custom_tool_call", "tool_call", "web_search_call":
            let name = payload["name"] as? String ?? payloadType
            return ImportedRecord(
                timestamp: timestamp,
                kind: .toolCall,
                observedAttribution: .agent,
                observedAttributionNote: "Tool invocation issued by the agent",
                summary: "Tool call: \(name)",
                detail: "",
                recordType: "tool_call"
            )
        case "function_call_output", "custom_tool_call_output", "tool_output":
            return ImportedRecord(
                timestamp: timestamp,
                kind: .toolOutput,
                observedAttribution: .agent,
                observedAttributionNote: "Tool output returned to the agent",
                summary: "Tool output",
                detail: JSONParsing.text(from: payload["output"], limit: 200),
                recordType: "tool_output"
            )
        default:
            return nil
        }
    }
}
