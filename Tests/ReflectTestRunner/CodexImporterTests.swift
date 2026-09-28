import Foundation
@testable import ReflectLib

struct CodexImporterTests {
    static let suiteName = "CodexImporterTests"
    private let epochStart = Date(timeIntervalSince1970: 1_767_603_600) // 2026-01-05T09:00:00Z

    func parsesSessionMetaAsSessionStart() throws {
        let record = try require(CodexImporter().parse(
            line: #"{"timestamp":"2026-01-05T09:00:00Z","type":"session_meta","payload":{"id":"fixture-session-1"}}"#
        ), "session_meta line should parse")
        try expectEqual(record.kind, .sessionStart)
        try expectEqual(record.recordType, "session_meta")
        try expectEqual(record.timestamp, epochStart)
    }

    func userRoleIsObservedAsUnclearWithNote() throws {
        let record = try require(CodexImporter().parse(
            line: #"{"timestamp":"2026-01-05T09:00:05Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Synthetic."}]}}"#
        ), "user message line should parse")
        try expectEqual(record.kind, .userMessage)
        try expectEqual(record.observedAttribution, .unclear)
        try expectTrue(record.observedAttributionNote.lowercased().contains("user"), "note must mention the observed user role")
    }

    func assistantRoleIsObservedAsAgent() throws {
        let record = try require(CodexImporter().parse(
            line: #"{"timestamp":"2026-01-05T09:01:20Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Synthetic."}]}}"#
        ), "assistant message line should parse")
        try expectEqual(record.kind, .agentMessage)
        try expectEqual(record.observedAttribution, .agent)
    }

    func toolCallsAreObservedAsAgent() throws {
        let call = try require(CodexImporter().parse(
            line: #"{"timestamp":"2026-01-05T09:01:00Z","type":"response_item","payload":{"type":"function_call","name":"shell"}}"#
        ), "function_call line should parse")
        try expectEqual(call.kind, .toolCall)
        try expectEqual(call.observedAttribution, .agent)

        let output = try require(CodexImporter().parse(
            line: #"{"timestamp":"2026-01-05T09:01:10Z","type":"response_item","payload":{"type":"function_call_output","output":"ok"}}"#
        ), "function_call_output line should parse")
        try expectEqual(output.kind, .toolOutput)
    }

    func skipsNonJSONUnknownTypesAndEmptyLines() throws {
        let importer = CodexImporter()
        try expectNil(importer.parse(line: "not json"))
        try expectNil(importer.parse(line: ""))
        try expectNil(importer.parse(line: #"{"timestamp":"2026-01-05T09:02:00Z","type":"some_future_type"}"#))
    }

    func engineBuildsStableEventsFromFixtureFile() throws {
        let dir = Fixtures.makeTempDirectory("codex")
        let file = dir.appendingPathComponent("rollout-fixture.jsonl")
        Fixtures.write(Fixtures.codexFixtureText, to: file)

        let events = JSONLImportEngine(
            importer: CodexImporter(),
            fileURL: file,
            sourceName: "Codex CLI",
            maxPreviewCharacters: 160
        ).run()

        // 7 parsed lines: 6 with exact timestamps + 1 falling back to file mtime.
        try expectEqual(events.count, 7)
        try expectTrue(events.contains { $0.kind == .sessionStart }, "session start must be present")
        try expectTrue(events.contains { $0.timestamp == epochStart && !$0.timestampApproximate }, "explicit timestamp must be preserved")
        try expectEqual(events.filter(\.timestampApproximate).count, 1)

        try expectTrue(events.allSatisfy { $0.sourceKind == .codex }, "source kind must be codex")
        try expectTrue(events.allSatisfy { $0.sourceName == "Codex CLI" }, "source name must be Codex CLI")
        try expectTrue(events.allSatisfy { $0.evidencePath == file.path }, "evidence path must point at the file")
        try expectTrue(events.allSatisfy { !$0.id.isEmpty }, "ids must be non-empty")
        try expectEqual(Set(events.map(\.id)).count, events.count, "evidence ids must be unique per line")
        try expectTrue(events.allSatisfy { $0.detail.count <= 160 }, "preview must be capped")
    }

    static var entries: [TestEntry] {
        let tests = CodexImporterTests()
        return [
            TestEntry(suite: suiteName, name: "parsesSessionMetaAsSessionStart") { try tests.parsesSessionMetaAsSessionStart() },
            TestEntry(suite: suiteName, name: "userRoleIsObservedAsUnclearWithNote") { try tests.userRoleIsObservedAsUnclearWithNote() },
            TestEntry(suite: suiteName, name: "assistantRoleIsObservedAsAgent") { try tests.assistantRoleIsObservedAsAgent() },
            TestEntry(suite: suiteName, name: "toolCallsAreObservedAsAgent") { try tests.toolCallsAreObservedAsAgent() },
            TestEntry(suite: suiteName, name: "skipsNonJSONUnknownTypesAndEmptyLines") { try tests.skipsNonJSONUnknownTypesAndEmptyLines() },
            TestEntry(suite: suiteName, name: "engineBuildsStableEventsFromFixtureFile") { try tests.engineBuildsStableEventsFromFixtureFile() }
        ]
    }
}
