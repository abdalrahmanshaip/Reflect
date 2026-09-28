import Foundation
@testable import ReflectLib

struct ClaudeAndCopilotImporterTests {
    static let suiteName = "ClaudeAndCopilotImporterTests"

    func claudeCodeUserIsUnclearAssistantIsAgent() throws {
        let importer = ClaudeCodeImporter()
        let user = try require(importer.parse(
            line: #"{"type":"user","message":{"role":"user","content":"Synthetic prompt."},"timestamp":"2026-02-06T10:00:00Z","sessionId":"fixture-cc-1"}"#
        ), "claude user line should parse")
        try expectEqual(user.kind, .userMessage)
        try expectEqual(user.observedAttribution, .unclear)

        let assistant = try require(importer.parse(
            line: #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Synthetic reply."}]},"timestamp":"2026-02-06T10:00:20Z","sessionId":"fixture-cc-1"}"#
        ), "claude assistant line should parse")
        try expectEqual(assistant.kind, .agentMessage)
        try expectEqual(assistant.observedAttribution, .agent)
    }

    func claudeCodeSummaryAndSystemAreRecognized() throws {
        let importer = ClaudeCodeImporter()
        let summary = try require(importer.parse(
            line: #"{"type":"summary","summary":"Fixture summary","timestamp":"2026-02-06T10:05:00Z"}"#
        ), "summary line should parse")
        try expectEqual(summary.kind, .summary)

        let system = try require(importer.parse(
            line: #"{"type":"system","subtype":"init","timestamp":"2026-02-06T09:59:00Z"}"#
        ), "system line should parse")
        try expectEqual(system.kind, .systemEvent)
    }

    func claudeCodeSkipsUnknownTypes() throws {
        try expectNil(ClaudeCodeImporter().parse(line: #"{"type":"brand_new_type"}"#))
    }

    func copilotImporterClassifiesTolerantly() throws {
        let importer = CopilotCLIImporter()
        let user = try require(importer.parse(
            line: #"{"type":"user.message","timestamp":"2026-03-07T11:00:00Z","content":"Synthetic Copilot input"}"#
        ), "copilot user line should parse")
        try expectEqual(user.kind, .userMessage)
        try expectEqual(user.observedAttribution, .unclear)

        let agent = try require(importer.parse(
            line: #"{"type":"assistant.message","timestamp":"2026-03-07T11:00:10Z"}"#
        ), "copilot agent line should parse")
        try expectEqual(agent.kind, .agentMessage)
        try expectEqual(agent.observedAttribution, .agent)

        let tool = try require(importer.parse(
            line: #"{"type":"tool.invoked","timestamp":"2026-03-07T11:00:20Z"}"#
        ), "copilot tool line should parse")
        try expectEqual(tool.kind, .toolCall)
    }

    func copilotImporterSkipsUnknown() throws {
        try expectNil(CopilotCLIImporter().parse(line: #"{"type":"totally_new.event"}"#))
        try expectNil(CopilotCLIImporter().parse(line: "broken"))
    }

    static var entries: [TestEntry] {
        let tests = ClaudeAndCopilotImporterTests()
        return [
            TestEntry(suite: suiteName, name: "claudeCodeUserIsUnclearAssistantIsAgent") { try tests.claudeCodeUserIsUnclearAssistantIsAgent() },
            TestEntry(suite: suiteName, name: "claudeCodeSummaryAndSystemAreRecognized") { try tests.claudeCodeSummaryAndSystemAreRecognized() },
            TestEntry(suite: suiteName, name: "claudeCodeSkipsUnknownTypes") { try tests.claudeCodeSkipsUnknownTypes() },
            TestEntry(suite: suiteName, name: "copilotImporterClassifiesTolerantly") { try tests.copilotImporterClassifiesTolerantly() },
            TestEntry(suite: suiteName, name: "copilotImporterSkipsUnknown") { try tests.copilotImporterSkipsUnknown() }
        ]
    }
}
