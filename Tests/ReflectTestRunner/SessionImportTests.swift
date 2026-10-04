import Foundation
@testable import ReflectLib

/// M2 slice 1 coverage for normalized Codex session/turn import: ordered
/// turns with roles and full retained text, stable identities, idempotent
/// re-imports, linked revisions for amended records, appended/resumed files,
/// malformed and missing-metadata handling, and fail-closed behavior on a
/// damaged sessions store. Every fixture is synthetic text in a fresh
/// temporary directory; source files are never written; no real history is
/// ever read.
struct SessionImportTests {
    static let suiteName = "SessionImportTests"

    private let now = Date(timeIntervalSince1970: 1_767_614_400) // 2026-01-05T12:00:00Z

    // MARK: Synthetic JSONL builders

    private func metaLine(id: String?, timestamp: String?) -> String {
        var fields: [String] = []
        if let timestamp { fields.append(#""timestamp":"\#(timestamp)""#) }
        fields.append(#""type":"session_meta""#)
        let payload = id.map { #"{"id":"\#($0)"}"# } ?? "{}"
        fields.append(#""payload":\#(payload)"#)
        return "{" + fields.joined(separator: ",") + "}"
    }

    private func messageLine(id: String?, role: String, text: String, timestamp: String?) -> String {
        var payloadFields: [String] = []
        payloadFields.append(#""type":"message""#)
        payloadFields.append(#""role":"\#(role)""#)
        if let id { payloadFields.append(#""id":"\#(id)""#) }
        payloadFields.append(#""content":[{"type":"input_text","text":"\#(text)"}]"#)
        var fields: [String] = []
        if let timestamp { fields.append(#""timestamp":"\#(timestamp)""#) }
        fields.append(#""type":"response_item""#)
        fields.append(#""payload":{\#(payloadFields.joined(separator: ","))}"#)
        return "{" + fields.joined(separator: ",") + "}"
    }

    private func writeFixture(_ lines: [String], name: String) -> URL {
        let dir = Fixtures.makeTempDirectory("session-import-\(name)")
        let file = dir.appendingPathComponent("rollout-fixture-\(name).jsonl")
        Fixtures.write(lines.joined(separator: "\n") + "\n", to: file)
        return file
    }

    private func makeService(_ directory: URL) -> SessionImportService {
        SessionImportService(persistence: PersistenceController(directory: directory))
    }

    private func assertImported(
        _ outcome: SessionImportOutcome,
        addedSessions: Int = 0,
        addedTurns: Int = 0,
        revisedTurns: Int = 0,
        context: String
    ) throws {
        guard case .imported(let sessionID, let sourceID, let sessions, let turns, let revised, _) = outcome else {
            throw TestFailure("\(context): expected an imported outcome, got \(outcome)")
        }
        try expectEqual(sessions, addedSessions, "\(context): added sessions")
        try expectEqual(turns, addedTurns, "\(context): added turns")
        try expectEqual(revised, revisedTurns, "\(context): revised turns")
        try expectFalse(sessionID.isEmpty, "\(context): stable session id must be present")
        _ = sourceID
    }

    private func longSyntheticText() -> String {
        String(repeating: "Synthetic retained context sentence. ", count: 12)
    }

    /// The full-featured synthetic Codex rollout fixture: session meta with an
    /// ID, a long user message with a source turn ID, reasoning, tool call
    /// and output, an assistant message, a known non-conversational record,
    /// an unknown future record, a malformed line, and a message with no
    /// timestamp.
    private func fullFixtureLines() -> [String] {
        [
            metaLine(id: "fixture-session-77", timestamp: "2026-01-05T09:00:00Z"),
            messageLine(id: "src-turn-1", role: "user", text: longSyntheticText(), timestamp: "2026-01-05T09:00:05Z"),
            #"{"timestamp":"2026-01-05T09:00:30Z","type":"response_item","payload":{"type":"reasoning","summary":[]}}"#,
            #"{"timestamp":"2026-01-05T09:01:00Z","type":"response_item","payload":{"type":"function_call","name":"shell","arguments":"{\"cmd\":[\"echo\",\"fixture\"]}"}}"#,
            #"{"timestamp":"2026-01-05T09:01:10Z","type":"response_item","payload":{"type":"function_call_output","output":"fixture tool output"}}"#,
            messageLine(id: nil, role: "assistant", text: "Synthetic assistant reply stating all fixture checks pass.", timestamp: "2026-01-05T09:01:20Z"),
            #"{"type":"event_msg","payload":{"type":"token_count"}}"#,
            #"{"timestamp":"2026-01-05T09:02:00Z","type":"some_future_type"}"#,
            "this line is deliberately not json",
            messageLine(id: nil, role: "user", text: "Synthetic turn without a timestamp.", timestamp: nil)
        ]
    }

    /// A synthetic session containing a repeated identical pair: two
    /// same-role records with identical text and identical observed time at
    /// different lines, plus one distinct assistant record.
    private func repeatedPairLines() -> [String] {
        [
            metaLine(id: "fixture-session-pair", timestamp: "2026-01-05T09:00:00Z"),
            messageLine(id: nil, role: "user", text: "Synthetic repeated pair record.", timestamp: "2026-01-05T09:00:05Z"),
            messageLine(id: nil, role: "user", text: "Synthetic repeated pair record.", timestamp: "2026-01-05T09:00:05Z"),
            messageLine(id: nil, role: "assistant", text: "Synthetic repeated pair reply.", timestamp: "2026-01-05T09:00:10Z")
        ]
    }

    // MARK: Normalization and ordering

    func normalizesOrderedTurnsWithRolesAndRetainedText() throws {
        let file = writeFixture(fullFixtureLines(), name: "ordered")
        let service = makeService(Fixtures.makeTempDirectory("ordered-store"))

        let outcome = service.importCodexSessionFile(at: file, now: now)
        try assertImported(outcome, addedSessions: 1, addedTurns: 6, context: "first import")
        guard case .imported(_, let sourceID, _, _, _, let scan) = outcome else {
            throw TestFailure("expected an imported outcome")
        }
        try expectEqual(sourceID, "fixture-session-77", "the source session ID must be preserved")
        try expectEqual(scan.recordLineCount, 10)
        try expectEqual(scan.malformedLineCount, 1)
        try expectEqual(scan.skippedRecordCount, 2)

        let sessions = try service.persistence.loadSessions()
        try expectEqual(sessions.count, 1)
        let session = try require(sessions.first)
        try expectEqual(session.sourceKind, SourceKind.codex)
        try expectEqual(session.sourceSessionID, "fixture-session-77")
        try expectEqual(session.title, nil, "no source title means unknown, never inferred")
        try expectEqual(session.project, nil)
        try expectEqual(session.importRevision, 1)
        try expectEqual(session.startedAt, Date(timeIntervalSince1970: 1_767_603_600), "session start comes from the meta record")
        try expectEqual(session.lastActivityAt, Date(timeIntervalSince1970: 1_767_603_680), "latest observed turn time")
        try expectEqual(session.turnIDs, session.turns.map(\.id), "ordered turn IDs match the ordered turns")

        let roles = session.turns.map(\.role)
        try expectEqual(roles, [.user, .reasoning, .tool, .tool, .assistant, .user], "turns keep source record order")
        try expectEqual(session.turns.map(\.sequence), Array(0..<6))

        let firstTurn = session.turns[0]
        try expectEqual(firstTurn.sourceTurnID, "src-turn-1")
        try expectEqual(firstTurn.sourceLine, 2)
        try expectEqual(firstTurn.sourcePath, file.path)
        try expectEqual(firstTurn.retainedText, longSyntheticText(), "full selected text is retained, not capped like event previews")
        try expectFalse(firstTurn.retainedTextTruncated)
        try expectTrue(firstTurn.previewTruncated, "the display preview is capped independently")
        try expectTrue(firstTurn.localPreview.count < firstTurn.retainedText.count)
        try expectEqual(firstTurn.timestamp, Date(timeIntervalSince1970: 1_767_603_605))

        let untimed = session.turns[5]
        try expectNil(untimed.timestamp, "a missing source time stays absent, never fabricated")
        try expectTrue(untimed.timestampApproximate)
        try expectEqual(session.coverage.turnCount, 6)
        try expectEqual(session.coverage.approximateTimestampTurnCount, 1)
        try expectEqual(session.coverage.truncatedRetainedTextTurnCount, 0)
        try expectFalse(session.coverage.missingSessionIdentity)
        try expectEqual(session.coverage.parserVersion, "codex-sessions/1")
        try expectTrue(session.coverage.parserUncertaintyNotes.contains(CodexSessionImporter.uncertaintyMalformedLines))
        try expectTrue(session.coverage.parserUncertaintyNotes.contains(CodexSessionImporter.uncertaintySkippedRecords))
    }

    func userRoleTurnsRemainExplicitlyAmbiguous() throws {
        let lines = [
            metaLine(id: "fixture-session-amb", timestamp: "2026-01-05T09:00:00Z"),
            messageLine(id: nil, role: "user", text: "Synthetic injected-capable record.", timestamp: "2026-01-05T09:00:05Z"),
            messageLine(id: nil, role: "assistant", text: "Synthetic agent reply.", timestamp: "2026-01-05T09:00:10Z")
        ]
        let file = writeFixture(lines, name: "ambiguity")
        let service = makeService(Fixtures.makeTempDirectory("ambiguity-store"))
        _ = service.importCodexSessionFile(at: file, now: now)

        let turns = try require(try service.persistence.loadSessions().first?.turns)
        let userTurn = try require(turns.first { $0.role == .user })
        try expectEqual(userTurn.observedAttribution, Attribution.unclear)
        try expectTrue(
            userTurn.observedAttributionNote.lowercased().contains("not asserted as human authorship"),
            "the note must state that human authorship is not asserted"
        )
        let assistantTurn = try require(turns.first { $0.role == .assistant })
        try expectEqual(assistantTurn.observedAttribution, Attribution.agent, "assistant role is an observed structural fact only")
    }

    func retainedTextCappedAtLimitIsLabeled() throws {
        let lines = [
            metaLine(id: "fixture-session-cap", timestamp: nil),
            messageLine(id: nil, role: "assistant", text: "One two three four five six seven.", timestamp: "2026-01-05T09:00:05Z")
        ]
        let file = writeFixture(lines, name: "cap")
        let service = SessionImportService(
            persistence: PersistenceController(directory: Fixtures.makeTempDirectory("cap-store")),
            importer: CodexSessionImporter(limits: .init(retainedTextCharacterLimit: 10, previewCharacterLimit: 4))
        )
        _ = service.importCodexSessionFile(at: file, now: now)

        let turn = try require(try service.persistence.loadSessions().first?.turns.first)
        try expectEqual(turn.retainedText, "One two th", "retention caps the retained text at the limit")
        try expectTrue(turn.retainedTextTruncated)
        try expectEqual(turn.localPreview, "One …")
        try expectTrue(turn.previewTruncated)
        try expectEqual(try require(try service.persistence.loadSessions().first).coverage.truncatedRetainedTextTurnCount, 1)
    }

    // MARK: Identity and read-only behavior

    func sourceFixtureBytesAreUnchangedByImport() throws {
        let file = writeFixture(fullFixtureLines(), name: "readonly")
        let original = try Data(contentsOf: file)

        let service = makeService(Fixtures.makeTempDirectory("readonly-store"))
        _ = service.importCodexSessionFile(at: file, now: now)

        try expectEqual(try Data(contentsOf: file), original, "import must be read-only on the source file")
    }

    func sessionIdentityFromSourceIDIsPathIndependent() throws {
        let lines = [
            metaLine(id: "fixture-session-pathfree", timestamp: "2026-01-05T09:00:00Z"),
            messageLine(id: nil, role: "user", text: "Synthetic path independence check.", timestamp: "2026-01-05T09:00:05Z")
        ]
        let first = writeFixture(lines, name: "pathfree-a")
        let second = writeFixture(lines, name: "pathfree-b")

        let firstOutcome = makeService(Fixtures.makeTempDirectory("pathfree-store-a")).importCodexSessionFile(at: first, now: now)
        let secondOutcome = makeService(Fixtures.makeTempDirectory("pathfree-store-b")).importCodexSessionFile(at: second, now: now)
        guard case .imported(let firstID, _, _, _, _, _) = firstOutcome,
              case .imported(let secondID, _, _, _, _, _) = secondOutcome else {
            throw TestFailure("expected imported outcomes")
        }
        try expectEqual(firstID, secondID, "a source session ID gives the same stable identity regardless of file path")
    }

    func missingMetadataYieldsStableFileScopedIdentity() throws {
        let lines = [
            messageLine(id: nil, role: "user", text: "Synthetic record without session metadata.", timestamp: "2026-01-05T09:00:05Z"),
            messageLine(id: nil, role: "assistant", text: "Synthetic reply without session metadata.", timestamp: nil),
            "deliberately broken line"
        ]
        let file = writeFixture(lines, name: "nometa")
        let directory = Fixtures.makeTempDirectory("nometa-store")
        let service = makeService(directory)

        let first = service.importCodexSessionFile(at: file, now: now)
        try assertImported(first, addedSessions: 1, addedTurns: 2, context: "no-meta import")
        guard case .imported(let stableID, let sourceID, _, _, _, let scan) = first else {
            throw TestFailure("expected an imported outcome")
        }
        try expectNil(sourceID, "no meta means no source session ID")
        try expectEqual(stableID, SessionIdentity.sessionID(source: .codex, sourceSessionID: nil, filePath: file.path))
        try expectEqual(scan.malformedLineCount, 1)

        let session = try require(try service.persistence.loadSessions().first)
        try expectTrue(session.coverage.missingSessionIdentity, "absent session identity must be reported")
        try expectTrue(
            session.coverage.parserUncertaintyNotes.contains(CodexSessionImporter.uncertaintyMalformedLines),
            "malformed lines must be noted as parser uncertainty"
        )
        try expectEqual(session.coverage.approximateTimestampTurnCount, 1)

        let again = service.importCodexSessionFile(at: file, now: now)
        try assertImported(again, addedSessions: 0, addedTurns: 0, revisedTurns: 0, context: "no-meta reimport")
        try expectEqual(try require(try service.persistence.loadSessions().first).id, stableID, "file-scoped identity is stable across imports of the same file")
    }

    // MARK: Idempotency, amendments, appends, resumes

    func identicalReimportIsIdempotentAndDoesNotRewriteTheStore() throws {
        let file = writeFixture(fullFixtureLines(), name: "idempotent")
        let directory = Fixtures.makeTempDirectory("idempotent-store")
        let service = makeService(directory)

        _ = service.importCodexSessionFile(at: file, now: now)
        let storeURL = directory.appendingPathComponent("sessions.json")
        let bytesAfterFirst = try Data(contentsOf: storeURL)
        let sessionsAfterFirst = try service.persistence.loadSessions()

        let second = service.importCodexSessionFile(at: file, now: now)
        try assertImported(second, addedSessions: 0, addedTurns: 0, revisedTurns: 0, context: "identical reimport")

        try expectEqual(try service.persistence.loadSessions(), sessionsAfterFirst, "identical reimport changes no record")
        try expectEqual(try Data(contentsOf: storeURL), bytesAfterFirst, "an unchanged merge must not rewrite the store file")
        try expectEqual(try require(sessionsAfterFirst.first).importRevision, 1)
    }

    func changedSourceRecordCreatesLinkedRevision() throws {
        var lines = fullFixtureLines()
        let file = writeFixture(lines, name: "amended")
        let directory = Fixtures.makeTempDirectory("amended-store")
        let service = makeService(directory)
        _ = service.importCodexSessionFile(at: file, now: now)

        let before = try require(try service.persistence.loadSessions().first)
        let turnBefore = before.turns[0]
        try expectEqual(turnBefore.revisions.count, 1)

        let amendedText = "Synthetic amended record text, corrected by the source."
        lines[1] = messageLine(id: "src-turn-1", role: "user", text: amendedText, timestamp: "2026-01-05T09:00:05Z")
        Fixtures.write(lines.joined(separator: "\n") + "\n", to: file)

        let second = service.importCodexSessionFile(at: file, now: now)
        try assertImported(second, addedTurns: 0, revisedTurns: 1, context: "amended reimport")

        let after = try require(try service.persistence.loadSessions().first)
        try expectEqual(after.id, before.id, "the stable session identity must not change")
        try expectEqual(after.importRevision, 2, "a content change bumps the session import revision")
        try expectEqual(after.turns.count, before.turns.count, "an amendment must not duplicate the session")

        let turnAfter = after.turns[0]
        try expectEqual(turnAfter.id, turnBefore.id, "the stable turn identity must not change")
        try expectEqual(turnAfter.sequence, 0, "an amended turn keeps its position")
        try expectEqual(turnAfter.revisions.count, 2, "the amendment becomes a retained new revision")
        try expectEqual(turnAfter.revisions[0], turnBefore.revisions[0], "the earlier revision stays retained")
        try expectEqual(turnAfter.revisions[1].retainedText, amendedText, "the current revision carries the amended content")
        try expectEqual(turnAfter.localPreview, turnAfter.revisions[1].localPreview)
        try expectNotEqual(turnAfter.revisions[1].revisionID, turnAfter.revisions[0].revisionID)
        try expectEqual(turnAfter.revisions[1].timestamp, turnBefore.revisions[0].timestamp, "unchanged observed time stays attached")
    }

    func appendedLinesExtendTheSessionWithNewTurns() throws {
        let lines = fullFixtureLines()
        let file = writeFixture(lines, name: "appended")
        let directory = Fixtures.makeTempDirectory("appended-store")
        let service = makeService(directory)
        _ = service.importCodexSessionFile(at: file, now: now)

        let before = try require(try service.persistence.loadSessions().first)
        var extended = lines
        extended.append(messageLine(id: nil, role: "user", text: "Synthetic appended question.", timestamp: "2026-01-05T09:03:00Z"))
        extended.append(messageLine(id: nil, role: "assistant", text: "Synthetic appended answer.", timestamp: "2026-01-05T09:03:30Z"))
        Fixtures.write(extended.joined(separator: "\n") + "\n", to: file)

        let second = service.importCodexSessionFile(at: file, now: now)
        try assertImported(second, addedTurns: 2, context: "appended reimport")

        let after = try require(try service.persistence.loadSessions().first)
        try expectEqual(after.id, before.id)
        try expectEqual(after.importRevision, 2)
        try expectEqual(after.turns.count, 8)
        try expectEqual(after.turns.map(\.sequence), Array(0..<8))
        for (index, turn) in before.turns.enumerated() {
            try expectEqual(after.turns[index], turn, "existing turns are unchanged by an append")
        }
        try expectEqual(after.turns[6].retainedText, "Synthetic appended question.")
        try expectEqual(after.turns[7].retainedText, "Synthetic appended answer.")
        try expectEqual(after.lastActivityAt, Date(timeIntervalSince1970: 1_767_603_810), "the latest appended observed time extends activity")
        try expectEqual(after.coverage.turnCount, 8)
    }

    func resumedReplayWithoutRecordIDsDoesNotDuplicateTurns() throws {
        let replayedTurns = [
            messageLine(id: nil, role: "user", text: "Synthetic resumed work question.", timestamp: "2026-01-05T09:00:05Z"),
            messageLine(id: nil, role: "assistant", text: "Synthetic resumed work answer.", timestamp: "2026-01-05T09:00:40Z")
        ]
        let first = writeFixture([metaLine(id: "fixture-session-resume", timestamp: "2026-01-05T09:00:00Z")] + replayedTurns, name: "resume-a")
        // A resumed rollout under a different path that replays the same
        // records without per-record IDs.
        let second = writeFixture([metaLine(id: "fixture-session-resume", timestamp: "2026-01-05T09:00:00Z")] + replayedTurns, name: "resume-b")
        let directory = Fixtures.makeTempDirectory("resume-store")
        let service = makeService(directory)

        _ = service.importCodexSessionFile(at: first, now: now)
        let replay = service.importCodexSessionFile(at: second, now: now)
        try assertImported(replay, addedTurns: 0, revisedTurns: 0, context: "resumed replay")

        let sessions = try service.persistence.loadSessions()
        try expectEqual(sessions.count, 1, "the same source session ID stays one session")
        try expectEqual(try require(sessions.first).turns.count, 2, "replayed content adds no duplicate turns")
    }

    func copiedFileDoesNotDuplicateTurns() throws {
        let lines = fullFixtureLines()
        let first = writeFixture(lines, name: "copy-a")
        let second = writeFixture(lines, name: "copy-b")
        let directory = Fixtures.makeTempDirectory("copy-store")
        let service = makeService(directory)

        _ = service.importCodexSessionFile(at: first, now: now)
        let copy = service.importCodexSessionFile(at: second, now: now)
        try assertImported(copy, addedTurns: 0, revisedTurns: 0, context: "duplicate export")

        let sessions = try service.persistence.loadSessions()
        try expectEqual(sessions.count, 1)
        try expectEqual(try require(sessions.first).turns.count, 6, "a duplicated export adds no turns, with or without record IDs")
    }

    /// Two same-role records with identical text and identical observed time
    /// at different lines of one file are distinct source records: both are
    /// retained as separate stable turns, and re-scanning the file preserves
    /// both without duplication.
    func distinctIdenticalTurnsInOneFileAreBothPreserved() throws {
        let file = writeFixture(repeatedPairLines(), name: "pair")
        let directory = Fixtures.makeTempDirectory("pair-store")
        let service = makeService(directory)

        let first = service.importCodexSessionFile(at: file, now: now)
        try assertImported(first, addedSessions: 1, addedTurns: 3, context: "pair import")

        let session = try require(try service.persistence.loadSessions().first)
        try expectEqual(session.turns.count, 3)
        let firstPairTurn = session.turns[0]
        let secondPairTurn = session.turns[1]
        try expectEqual(firstPairTurn.role, ConversationRole.user)
        try expectEqual(secondPairTurn.role, ConversationRole.user)
        try expectEqual(firstPairTurn.retainedText, secondPairTurn.retainedText, "the two records carry identical content")
        try expectEqual(firstPairTurn.timestamp, secondPairTurn.timestamp, "the two records also carry the identical observed time")
        try expectNotEqual(firstPairTurn.id, secondPairTurn.id, "distinct source lines are distinct stable turns")
        try expectEqual(firstPairTurn.sourceLine, 2)
        try expectEqual(secondPairTurn.sourceLine, 3)
        try expectEqual(session.turns[2].sourceLine, 4)

        let again = service.importCodexSessionFile(at: file, now: now)
        try assertImported(again, addedSessions: 0, addedTurns: 0, revisedTurns: 0, context: "pair reimport")
        try expectEqual(
            try require(try service.persistence.loadSessions().first).turns.count,
            3,
            "re-scanning the same file preserves both identical turns without duplication"
        )
    }

    /// A byte-exact copy of a file that contains the repeated identical pair
    /// adds no turns: every record is the same source record replayed in
    /// another file of the session (identical coordinate and content).
    func exactCopyOfFileWithRepeatedPairDoesNotDuplicate() throws {
        let lines = repeatedPairLines()
        let first = writeFixture(lines, name: "pair-copy-a")
        let second = writeFixture(lines, name: "pair-copy-b")
        let directory = Fixtures.makeTempDirectory("pair-copy-store")
        let service = makeService(directory)

        _ = service.importCodexSessionFile(at: first, now: now)
        let copy = service.importCodexSessionFile(at: second, now: now)
        try assertImported(copy, addedTurns: 0, revisedTurns: 0, context: "exact copy import")

        let sessions = try service.persistence.loadSessions()
        try expectEqual(sessions.count, 1)
        let session = try require(sessions.first)
        try expectEqual(session.turns.count, 3, "an exact copy of the file adds no turns, including the repeated identical pair")
        try expectEqual(session.turns[0].sourcePath, first.path, "the retained turns keep the first import's coordinates")
        try expectEqual(session.turns[1].sourcePath, first.path)
    }

    /// A response_item payload of a type this importer does not retain is a
    /// counted skip: it becomes no turn, it is not a malformed line, and the
    /// durable coverage note for omitted records appears exactly as the
    /// per-import scan reports it.
    func unsupportedResponseItemPayloadCountedInCoverage() throws {
        let lines = [
            metaLine(id: "fixture-session-unsupported", timestamp: "2026-01-05T09:00:00Z"),
            messageLine(id: nil, role: "user", text: "Synthetic supported record.", timestamp: "2026-01-05T09:00:05Z"),
            #"{"timestamp":"2026-01-05T09:00:20Z","type":"response_item","payload":{"type":"synthetic_unsupported_payload","detail":"not a retained record type"}}"#
        ]
        let file = writeFixture(lines, name: "unsupported-item")
        let directory = Fixtures.makeTempDirectory("unsupported-item-store")
        let service = makeService(directory)

        let outcome = service.importCodexSessionFile(at: file, now: now)
        try assertImported(outcome, addedSessions: 1, addedTurns: 1, context: "unsupported item import")
        guard case .imported(_, _, _, _, _, let scan) = outcome else {
            throw TestFailure("expected an imported outcome")
        }
        try expectEqual(scan.recordLineCount, 3)
        try expectEqual(scan.malformedLineCount, 0, "an unsupported payload is a skip, not a malformed line")
        try expectEqual(scan.skippedRecordCount, 1, "the unsupported response_item payload is counted as skipped")

        let session = try require(try service.persistence.loadSessions().first)
        try expectEqual(session.coverage.turnCount, 1, "only supported records become turns")
        try expectTrue(
            session.coverage.parserUncertaintyNotes.contains(CodexSessionImporter.uncertaintySkippedRecords),
            "the durable coverage must carry the omission note for the unsupported record"
        )
    }

    // MARK: Unsupported content and fail-closed store behavior

    func fileWithoutSupportedRecordsReportsNoSupportedRecords() throws {
        let lines = [
            "not json at all",
            #"{"type":"event_msg","payload":{"type":"token_count"}}"#,
            #"{"timestamp":"2026-01-05T09:02:00Z","type":"some_future_type"}"#
        ]
        let file = writeFixture(lines, name: "unsupported")
        let directory = Fixtures.makeTempDirectory("unsupported-store")
        let service = makeService(directory)

        let outcome = service.importCodexSessionFile(at: file, now: now)
        guard case .noSupportedRecords(let scan) = outcome else {
            throw TestFailure("expected a noSupportedRecords outcome, got \(outcome)")
        }
        try expectEqual(scan.recordLineCount, 3)
        try expectEqual(scan.malformedLineCount, 1)
        try expectEqual(scan.skippedRecordCount, 2)
        try expectFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("sessions.json").path), "nothing may be written for unsupported content")
    }

    func unreadableSourceFileFailsWithoutTouchingTheStore() throws {
        let directory = Fixtures.makeTempDirectory("unreadable-store")
        let service = makeService(directory)
        let missingFile = directory.appendingPathComponent("rollout-missing-fixture.jsonl")

        let outcome = service.importCodexSessionFile(at: missingFile, now: now)
        guard case .failed(let message) = outcome else {
            throw TestFailure("expected a failed outcome, got \(outcome)")
        }
        try expectFalse(message.contains(directory.path), "the failure must not expose private paths")
        try expectFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("sessions.json").path))
    }

    func corruptSessionsStoreFailsClosedOnImport() throws {
        let file = writeFixture(fullFixtureLines(), name: "corruptstore")
        let directory = Fixtures.makeTempDirectory("corruptstore-store")
        let storeURL = directory.appendingPathComponent("sessions.json")
        let damaged = Data("{\"synthetic-damaged-sessions-fixture\":".utf8)
        try damaged.write(to: storeURL)

        let service = makeService(directory)
        let outcome = service.importCodexSessionFile(at: file, now: now)
        guard case .failed(let message) = outcome else {
            throw TestFailure("a damaged sessions store must fail the import, got \(outcome)")
        }
        try expectFalse(message.isEmpty, "the failure must carry a safe message")
        try expectFalse(message.contains(directory.path), "the failure must not expose private paths")
        try expectEqual(try Data(contentsOf: storeURL), damaged, "the damaged store file must stay byte-for-byte untouched")
    }

    static var entries: [TestEntry] {
        let tests = SessionImportTests()
        return [
            TestEntry(suite: suiteName, name: "normalizesOrderedTurnsWithRolesAndRetainedText") {
                try tests.normalizesOrderedTurnsWithRolesAndRetainedText()
            },
            TestEntry(suite: suiteName, name: "userRoleTurnsRemainExplicitlyAmbiguous") {
                try tests.userRoleTurnsRemainExplicitlyAmbiguous()
            },
            TestEntry(suite: suiteName, name: "retainedTextCappedAtLimitIsLabeled") {
                try tests.retainedTextCappedAtLimitIsLabeled()
            },
            TestEntry(suite: suiteName, name: "sourceFixtureBytesAreUnchangedByImport") {
                try tests.sourceFixtureBytesAreUnchangedByImport()
            },
            TestEntry(suite: suiteName, name: "sessionIdentityFromSourceIDIsPathIndependent") {
                try tests.sessionIdentityFromSourceIDIsPathIndependent()
            },
            TestEntry(suite: suiteName, name: "missingMetadataYieldsStableFileScopedIdentity") {
                try tests.missingMetadataYieldsStableFileScopedIdentity()
            },
            TestEntry(suite: suiteName, name: "identicalReimportIsIdempotentAndDoesNotRewriteTheStore") {
                try tests.identicalReimportIsIdempotentAndDoesNotRewriteTheStore()
            },
            TestEntry(suite: suiteName, name: "changedSourceRecordCreatesLinkedRevision") {
                try tests.changedSourceRecordCreatesLinkedRevision()
            },
            TestEntry(suite: suiteName, name: "appendedLinesExtendTheSessionWithNewTurns") {
                try tests.appendedLinesExtendTheSessionWithNewTurns()
            },
            TestEntry(suite: suiteName, name: "resumedReplayWithoutRecordIDsDoesNotDuplicateTurns") {
                try tests.resumedReplayWithoutRecordIDsDoesNotDuplicateTurns()
            },
            TestEntry(suite: suiteName, name: "copiedFileDoesNotDuplicateTurns") {
                try tests.copiedFileDoesNotDuplicateTurns()
            },
            TestEntry(suite: suiteName, name: "distinctIdenticalTurnsInOneFileAreBothPreserved") {
                try tests.distinctIdenticalTurnsInOneFileAreBothPreserved()
            },
            TestEntry(suite: suiteName, name: "exactCopyOfFileWithRepeatedPairDoesNotDuplicate") {
                try tests.exactCopyOfFileWithRepeatedPairDoesNotDuplicate()
            },
            TestEntry(suite: suiteName, name: "unsupportedResponseItemPayloadCountedInCoverage") {
                try tests.unsupportedResponseItemPayloadCountedInCoverage()
            },
            TestEntry(suite: suiteName, name: "fileWithoutSupportedRecordsReportsNoSupportedRecords") {
                try tests.fileWithoutSupportedRecordsReportsNoSupportedRecords()
            },
            TestEntry(suite: suiteName, name: "unreadableSourceFileFailsWithoutTouchingTheStore") {
                try tests.unreadableSourceFileFailsWithoutTouchingTheStore()
            },
            TestEntry(suite: suiteName, name: "corruptSessionsStoreFailsClosedOnImport") {
                try tests.corruptSessionsStoreFailsClosedOnImport()
            }
        ]
    }
}
