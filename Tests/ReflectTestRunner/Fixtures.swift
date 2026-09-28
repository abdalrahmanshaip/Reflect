import Foundation
@testable import ReflectLib

enum Fixtures {
    static func makeTempDirectory(_ name: String) -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("reflect-tests-\(UUID().uuidString)", isDirectory: true)
        let dir = base.appendingPathComponent(name, isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func write(_ text: String, to url: URL) {
        try! text.data(using: .utf8)!.write(to: url)
    }

    // All fixture content below is synthetic. It never mirrors real user histories.
    static let codexFixtureText: String = """
    {"timestamp":"2026-01-05T09:00:00Z","type":"session_meta","payload":{"id":"fixture-session-1","cwd":"/tmp/fixture"}}
    {"timestamp":"2026-01-05T09:00:05Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Synthetic fixture prompt about a fictional test."}]}}
    {"timestamp":"2026-01-05T09:00:30Z","type":"response_item","payload":{"type":"reasoning","summary":[]}}
    {"timestamp":"2026-01-05T09:01:00Z","type":"response_item","payload":{"type":"function_call","name":"shell","arguments":"{\\"cmd\\":[\\"echo\\",\\"fixture\\"]}"}}
    {"timestamp":"2026-01-05T09:01:10Z","type":"response_item","payload":{"type":"function_call_output","output":"fixture output line"}}
    {"timestamp":"2026-01-05T09:01:20Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Synthetic fixture reply stating all fixture checks pass."}]}}
    {"type":"event_msg","payload":{"type":"token_count"}}
    this line is deliberately not json
    {"timestamp":"2026-01-05T09:02:00Z","type":"some_future_type"}
    """

    static let claudeFixtureText: String = """
    {"type":"user","message":{"role":"user","content":"Synthetic Claude Code prompt."},"timestamp":"2026-02-06T10:00:00Z","sessionId":"fixture-cc-1","cwd":"/tmp/fixture"}
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Synthetic Claude Code reply."}]},"timestamp":"2026-02-06T10:00:20Z","sessionId":"fixture-cc-1"}
    {"type":"summary","summary":"Fixture summary of a synthetic session","timestamp":"2026-02-06T10:05:00Z"}
    {"type":"system","subtype":"init","timestamp":"2026-02-06T09:59:00Z"}
    """

    static let copilotFixtureText: String = """
    {"type":"user.message","timestamp":"2026-03-07T11:00:00Z","content":"Synthetic Copilot CLI input"}
    {"type":"assistant.message","timestamp":"2026-03-07T11:00:10Z","content":"Synthetic Copilot CLI reply"}
    {"type":"tool.invoked","timestamp":"2026-03-07T11:00:20Z","tool":"terminal"}
    """

    @discardableResult
    static func codexSessionTree(in home: URL) -> URL {
        let sessions = home.appendingPathComponent(".codex/sessions/2026/01/05", isDirectory: true)
        try! FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        write(codexFixtureText, to: sessions.appendingPathComponent("rollout-2026-01-05T09-00-00-fixture.jsonl"))
        return sessions
    }

    @discardableResult
    static func claudeProjectTree(in home: URL) -> URL {
        let projects = home.appendingPathComponent(".claude/projects/fixture-project", isDirectory: true)
        try! FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        write(claudeFixtureText, to: projects.appendingPathComponent("fixture-session.jsonl"))
        return projects
    }

    @discardableResult
    static func copilotTree(in home: URL) -> URL {
        let dir = home.appendingPathComponent(".copilot/session-state/fixture-session", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        write(copilotFixtureText, to: dir.appendingPathComponent("events.jsonl"))
        return dir
    }

    /// A fixed reference moment: 2026-01-05 12:00:00 UTC.
    static let referenceDate = Date(timeIntervalSince1970: 1_767_614_400)

    /// Builds `count` synthetic events on a single local day, alternating sources.
    static func dayEvents(count: Int, base: Date = referenceDate) -> [EvidenceEvent] {
        let sources: [(SourceKind, String)] = [
            (.codex, "Codex CLI"),
            (.claudeCode, "Claude Code"),
            (.copilotCLI, "Copilot CLI")
        ]
        return (0..<count).map { i in
            let src = sources[i % sources.count]
            return EvidenceEvent(
                id: "fixture-event-\(i)",
                sourceKind: src.0,
                sourceName: src.1,
                timestamp: base.addingTimeInterval(TimeInterval(i * 60)),
                timestampApproximate: false,
                kind: i % 2 == 0 ? .agentMessage : .userMessage,
                summary: "Synthetic event \(i)",
                detail: "",
                evidencePath: "/tmp/fixture/file-\(i).jsonl",
                evidenceLine: i + 1,
                observedAttribution: i % 3 == 0 ? .agent : .unclear,
                observedAttributionNote: "Structural role in transcript",
                importedAt: base
            )
        }
    }

    // MARK: Git fixture

    @discardableResult
    static func initGitRepo(at repo: URL) throws -> String {
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        _ = try runGitCaptured(["init", "-q"], at: repo)
        _ = try runGitCaptured(["config", "user.name", "Fixture Author"], at: repo)
        _ = try runGitCaptured(["config", "user.email", "fixture-author@example.invalid"], at: repo)
        try "fixture\n".write(to: repo.appendingPathComponent("fixture.txt"), atomically: true, encoding: .utf8)
        _ = try runGitCaptured(["add", "fixture.txt"], at: repo)
        _ = try runGitCaptured(["commit", "-q", "-m", "Fixture commit"], at: repo)
        let (out, err, code) = try runGitCaptured(["rev-parse", "HEAD"], at: repo)
        try expectEqual(code, 0, "git rev-parse failed: \(err)")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func runGitCaptured(_ args: [String], at repo: URL) throws -> (String, String, Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = repo
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (out, err, process.terminationStatus)
    }
}
