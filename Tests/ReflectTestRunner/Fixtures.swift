import Foundation
@testable import ReflectLib

/// Event-driven handoff from detached async work back to synchronous tests.
final class AsyncResultBox<T>: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)
    private var value: T?

    func fulfill(_ newValue: T) {
        value = newValue
        semaphore.signal()
    }

    func take() -> T? {
        let taken = value
        value = nil
        return taken
    }
}

enum Fixtures {
    static func makeTempDirectory(_ name: String) -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("reflect-tests-\(UUID().uuidString)", isDirectory: true)
        let dir = base.appendingPathComponent(name, isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Awaits a nonisolated async operation from a synchronous test entry.
    /// The body must not require the main thread; completion is event-driven
    /// through a semaphore rather than sleep-based.
    static func awaitAsync<T: Sendable>(_ body: @escaping @Sendable () async -> T) throws -> T {
        let box = AsyncResultBox<T>()
        Task.detached(priority: .userInitiated) {
            let result = await body()
            box.fulfill(result)
        }
        guard box.semaphore.wait(timeout: .now() + 30) == .success else {
            throw TestFailure("async test work did not finish within 30s")
        }
        guard let value = box.take() else {
            throw TestFailure("async test work produced no value")
        }
        return value
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

    // MARK: Sessions store fixtures (M2, all synthetic)

    /// A synthetic normalized session used by sessions-store and migration
    /// tests. Mirrors `syntheticSessionsLegacyJSON` exactly.
    static func syntheticSession(
        id: String = "fixture-stable-session-1",
        sourceSessionID: String? = "fixture-session-77",
        importedAt: Date = referenceDate
    ) -> WorkSession {
        let startedAt = Date(timeIntervalSince1970: 1_767_603_605) // 2026-01-05T09:00:05Z
        let lastActivityAt = Date(timeIntervalSince1970: 1_767_603_680) // 2026-01-05T09:01:20Z
        let turns = [
            ConversationTurn(
                id: "fixture-turn-1",
                sessionID: id,
                role: .user,
                sourceTurnID: "fixture-source-turn-1",
                sourcePath: "/tmp/fixture/rollout-fixture.jsonl",
                sourceLine: 2,
                sequence: 0,
                observedAttribution: .unclear,
                observedAttributionNote: "Observed role 'user' in synthetic fixture",
                revisions: [
                    TurnRevision(
                        revisionID: "fixture-revision-1",
                        importedAt: importedAt,
                        timestamp: startedAt,
                        timestampApproximate: false,
                        retainedText: "Synthetic retained user turn text",
                        retainedTextTruncated: false,
                        localPreview: "Synthetic retained user turn text",
                        previewTruncated: false
                    )
                ]
            ),
            ConversationTurn(
                id: "fixture-turn-2",
                sessionID: id,
                role: .assistant,
                sourceTurnID: nil,
                sourcePath: "/tmp/fixture/rollout-fixture.jsonl",
                sourceLine: 6,
                sequence: 1,
                observedAttribution: .agent,
                observedAttributionNote: "Observed role 'assistant' in synthetic fixture",
                revisions: [
                    TurnRevision(
                        revisionID: "fixture-revision-2",
                        importedAt: importedAt,
                        timestamp: lastActivityAt,
                        timestampApproximate: false,
                        retainedText: "Synthetic retained assistant turn text",
                        retainedTextTruncated: false,
                        localPreview: "Synthetic retained assistant turn text",
                        previewTruncated: false
                    )
                ]
            )
        ]
        return WorkSession(
            id: id,
            sourceKind: .codex,
            sourceSessionID: sourceSessionID,
            title: nil,
            project: nil,
            importRevision: 1,
            firstImportedAt: importedAt,
            lastImportedAt: importedAt,
            startedAt: startedAt,
            startedAtApproximate: false,
            lastActivityAt: lastActivityAt,
            turns: turns,
            coverage: CoverageSummary(
                turnCount: turns.count,
                approximateTimestampTurnCount: 0,
                truncatedRetainedTextTurnCount: 0,
                missingSessionIdentity: sourceSessionID == nil,
                firstRecordedAt: startedAt,
                lastRecordedAt: lastActivityAt,
                parserVersion: "codex-sessions/1",
                parserUncertaintyNotes: []
            )
        )
    }

    /// Legacy bare-payload JSON (schema version 0) matching
    /// `syntheticSession()` exactly, so migration round-trips are checkable.
    static let syntheticSessionsLegacyJSON: String = """
    [
      {
        "coverage" : {
          "approximateTimestampTurnCount" : 0,
          "firstRecordedAt" : "2026-01-05T09:00:05Z",
          "lastRecordedAt" : "2026-01-05T09:01:20Z",
          "missingSessionIdentity" : false,
          "parserUncertaintyNotes" : [],
          "parserVersion" : "codex-sessions/1",
          "truncatedRetainedTextTurnCount" : 0,
          "turnCount" : 2
        },
        "firstImportedAt" : "2026-01-05T12:00:00Z",
        "id" : "fixture-stable-session-1",
        "importRevision" : 1,
        "lastActivityAt" : "2026-01-05T09:01:20Z",
        "lastImportedAt" : "2026-01-05T12:00:00Z",
        "project" : null,
        "sourceKind" : "codex",
        "sourceSessionID" : "fixture-session-77",
        "startedAt" : "2026-01-05T09:00:05Z",
        "startedAtApproximate" : false,
        "title" : null,
        "turns" : [
          {
            "id" : "fixture-turn-1",
            "observedAttribution" : "unclear",
            "observedAttributionNote" : "Observed role 'user' in synthetic fixture",
            "revisions" : [
              {
                "importedAt" : "2026-01-05T12:00:00Z",
                "localPreview" : "Synthetic retained user turn text",
                "previewTruncated" : false,
                "retainedText" : "Synthetic retained user turn text",
                "retainedTextTruncated" : false,
                "revisionID" : "fixture-revision-1",
                "timestamp" : "2026-01-05T09:00:05Z",
                "timestampApproximate" : false
              }
            ],
            "role" : "user",
            "sequence" : 0,
            "sessionID" : "fixture-stable-session-1",
            "sourceLine" : 2,
            "sourcePath" : "/tmp/fixture/rollout-fixture.jsonl",
            "sourceTurnID" : "fixture-source-turn-1"
          },
          {
            "id" : "fixture-turn-2",
            "observedAttribution" : "agent",
            "observedAttributionNote" : "Observed role 'assistant' in synthetic fixture",
            "revisions" : [
              {
                "importedAt" : "2026-01-05T12:00:00Z",
                "localPreview" : "Synthetic retained assistant turn text",
                "previewTruncated" : false,
                "retainedText" : "Synthetic retained assistant turn text",
                "retainedTextTruncated" : false,
                "revisionID" : "fixture-revision-2",
                "timestamp" : "2026-01-05T09:01:20Z",
                "timestampApproximate" : false
              }
            ],
            "role" : "assistant",
            "sequence" : 1,
            "sessionID" : "fixture-stable-session-1",
            "sourceLine" : 6,
            "sourcePath" : "/tmp/fixture/rollout-fixture.jsonl",
            "sourceTurnID" : null
          }
        ]
      }
    ]
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

    // MARK: Synthetic conversation fixtures (M3)

    /// A synthetic durable conversation used by conversations-store,
    /// versioning, migration, and conversation-service tests. Mirrors
    /// `syntheticConversationsLegacyJSON` exactly.
    static func syntheticStoredConversation(
        conversationID: String = "fixture-conversation-1",
        requestID: String = "fixture-conversation-request-1"
    ) -> StoredConversation {
        let reference = referenceDate
        let userMessage = ConversationMessage(
            id: "fixture-conversation-message-1",
            conversationID: conversationID,
            speaker: .user,
            text: "Synthetic fixture question.",
            createdAt: reference,
            requestID: requestID,
            transmission: .sent,
            requestOutcome: .completed(responseMessageID: "fixture-conversation-message-2"),
            usage: nil,
            referencedContextItemIDs: [],
            agentKind: nil,
            selectedModel: nil
        )
        let assistantMessage = ConversationMessage(
            id: "fixture-conversation-message-2",
            conversationID: conversationID,
            speaker: .assistant,
            text: "Synthetic fixture answer.",
            createdAt: reference,
            requestID: requestID,
            transmission: .sent,
            requestOutcome: nil,
            usage: nil,
            referencedContextItemIDs: [],
            agentKind: .codex,
            selectedModel: nil
        )
        return StoredConversation(
            record: ConversationRecord(
                id: conversationID,
                createdAt: reference,
                updatedAt: reference,
                messageIDs: [userMessage.id, assistantMessage.id],
                draftText: nil,
                draftUpdatedAt: nil
            ),
            messages: [userMessage, assistantMessage]
        )
    }

    /// Legacy bare-payload JSON (schema version 0) matching
    /// `syntheticStoredConversation()` exactly, so migration round-trips are
    /// checkable.
    static let syntheticConversationsLegacyJSON: String = """
    [
      {
        "messages" : [
          {
            "agentKind" : null,
            "conversationID" : "fixture-conversation-1",
            "createdAt" : "2026-01-05T12:00:00Z",
            "id" : "fixture-conversation-message-1",
            "referencedContextItemIDs" : [],
            "requestID" : "fixture-conversation-request-1",
            "requestOutcome" : {
              "completed" : {
                "responseMessageID" : "fixture-conversation-message-2"
              }
            },
            "selectedModel" : null,
            "speaker" : "user",
            "text" : "Synthetic fixture question.",
            "transmission" : "sent",
            "usage" : null
          },
          {
            "agentKind" : "codex",
            "conversationID" : "fixture-conversation-1",
            "createdAt" : "2026-01-05T12:00:00Z",
            "id" : "fixture-conversation-message-2",
            "referencedContextItemIDs" : [],
            "requestID" : "fixture-conversation-request-1",
            "requestOutcome" : null,
            "selectedModel" : null,
            "speaker" : "assistant",
            "text" : "Synthetic fixture answer.",
            "transmission" : "sent",
            "usage" : null
          }
        ],
        "record" : {
          "createdAt" : "2026-01-05T12:00:00Z",
          "draftText" : null,
          "draftUpdatedAt" : null,
          "id" : "fixture-conversation-1",
          "messageIDs" : [
            "fixture-conversation-message-1",
            "fixture-conversation-message-2"
          ],
          "updatedAt" : "2026-01-05T12:00:00Z"
        }
      }
    ]
    """
}
