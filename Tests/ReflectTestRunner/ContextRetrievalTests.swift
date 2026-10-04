import Foundation
@testable import ReflectLib

/// M2 slice 2 coverage for bounded local context retrieval: transparent
/// deterministic selection over persisted stores, earlier/recent comparison,
/// neighbor windows, item/byte/turn caps, honest coverage and uncertainty,
/// distinct provenance for corrections and self-reports, missing store and
/// damaged store distinguishability, and proof that retrieval never re-reads
/// sources. Every fixture is synthetic text in fresh temporary stores; no
/// real history is read, no provider is invoked, and no UI is involved.
struct ContextRetrievalTests {
    static let suiteName = "ContextRetrievalTests"

    private let now = Date(timeIntervalSince1970: 1_767_614_400) // 2026-01-05T12:00:00Z

    // MARK: Synthetic store fixtures

    private func makeTurn(
        id: String,
        sessionID: String,
        role: ConversationRole,
        text: String,
        sequence: Int,
        at: Date?,
        attribution: Attribution,
        note: String
    ) -> ConversationTurn {
        let revision = TurnRevision(
            revisionID: "rev-\(id)",
            importedAt: now,
            timestamp: at,
            timestampApproximate: at == nil,
            retainedText: text,
            retainedTextTruncated: false,
            localPreview: String(text.prefix(20)),
            previewTruncated: text.count > 20
        )
        return ConversationTurn(
            id: id,
            sessionID: sessionID,
            role: role,
            sourceTurnID: nil,
            sourcePath: "/tmp/synthetic/\(sessionID).jsonl",
            sourceLine: sequence + 2,
            sequence: sequence,
            observedAttribution: attribution,
            observedAttributionNote: note,
            revisions: [revision]
        )
    }

    private func makeSession(
        id: String,
        turns: [ConversationTurn],
        sourceSessionID: String?,
        startedAt: Date?,
        missingIdentity: Bool
    ) -> WorkSession {
        let timestamps = turns.compactMap { $0.revisions.last?.timestamp }
        return WorkSession(
            id: id,
            sourceKind: .codex,
            sourceSessionID: sourceSessionID,
            title: nil,
            project: nil,
            importRevision: 1,
            firstImportedAt: now,
            lastImportedAt: now,
            startedAt: startedAt,
            startedAtApproximate: false,
            lastActivityAt: timestamps.max(),
            turns: turns,
            coverage: CoverageSummary(
                turnCount: turns.count,
                approximateTimestampTurnCount: turns.filter { $0.timestampApproximate }.count,
                truncatedRetainedTextTurnCount: 0,
                missingSessionIdentity: missingIdentity,
                firstRecordedAt: timestamps.min(),
                lastRecordedAt: timestamps.max(),
                parserVersion: "codex-sessions/1",
                parserUncertaintyNotes: []
            )
        )
    }

    private func makeEvent(id: String, summary: String, detail: String = "", at: Date, path: String = "/tmp/synthetic/events.jsonl") -> EvidenceEvent {
        EvidenceEvent(
            id: id,
            sourceKind: .claudeCode,
            sourceName: "Claude Code",
            timestamp: at,
            timestampApproximate: false,
            kind: .userMessage,
            summary: summary,
            detail: detail,
            evidencePath: path,
            evidenceLine: 3,
            observedAttribution: .unclear,
            observedAttributionNote: "Observed role in synthetic fixture",
            importedAt: now
        )
    }

    private func makeReport(day: String, answers: [String: String], analysisResult: String? = nil, narrative: String = "") -> DailyReport {
        let entries = answers.mapValues { AnswerEntry(text: $0, updatedAt: now) }
        return DailyReport(
            day: day,
            narrative: narrative,
            narrativeGeneratedAt: narrative.isEmpty ? nil : now,
            answers: entries,
            analysisResult: analysisResult,
            analysisGeneratedAt: analysisResult == nil ? nil : now,
            updatedAt: now
        )
    }

    private func makePersistence(
        _ directory: URL,
        sessions: [WorkSession] = [],
        events: [EvidenceEvent] = [],
        corrections: [AttributionCorrection] = [],
        reports: [DailyReport] = []
    ) -> PersistenceController {
        let persistence = PersistenceController(directory: directory)
        if !sessions.isEmpty { try! persistence.saveSessions(sessions) }
        if !events.isEmpty { try! persistence.saveEvents(events) }
        if !corrections.isEmpty { try! persistence.saveCorrections(corrections) }
        if !reports.isEmpty { try! persistence.saveReports(reports) }
        return persistence
    }

    private func retrieve(
        _ persistence: PersistenceController,
        terms: [String],
        comparison: Bool = false,
        scope: ContextScope? = nil,
        budget: BoundedContextBudget = .retrievalDefault
    ) throws -> ContextEnvelope {
        let retriever = ContextRetriever(persistence: persistence)
        let request = ContextRetrievalRequest(
            terms: terms,
            requestsEarlierRecentComparison: comparison,
            scope: scope,
            budget: budget
        )
        return try retriever.retrieve(request, now: now)
    }

    // MARK: Earlier + recent comparison

    func comparisonSelectsEarlierAndRecentExamples() throws {
        let older = makeSession(
            id: "session-old",
            turns: [makeTurn(id: "old-turn", sessionID: "session-old", role: .user, text: "Synthetic debugging of a payment retry loop, early attempt.", sequence: 0, at: Date(timeIntervalSince1970: 1_767_230_400), attribution: .unclear, note: "Observed role 'user'")],
            sourceSessionID: "src-old",
            startedAt: Date(timeIntervalSince1970: 1_767_230_400),
            missingIdentity: false
        )
        let newer = makeSession(
            id: "session-new",
            turns: [makeTurn(id: "new-turn", sessionID: "session-new", role: .user, text: "Synthetic debugging of the payment retry loop again, recent attempt.", sequence: 0, at: Date(timeIntervalSince1970: 1_767_600_400), attribution: .unclear, note: "Observed role 'user'")],
            sourceSessionID: "src-new",
            startedAt: Date(timeIntervalSince1970: 1_767_600_400),
            missingIdentity: false
        )
        let persistence = makePersistence(Fixtures.makeTempDirectory("ctx-compare"), sessions: [older, newer])

        let envelope = try retrieve(persistence, terms: ["debugging", "payment"], comparison: true)

        try expectEqual(envelope.outcome, ContextOutcomeKind.historyIncluded)
        let ids = envelope.items.map(\.id)
        try expectTrue(ids.contains("old-turn"), "the earlier example must be included")
        try expectTrue(ids.contains("new-turn"), "the recent example must be included")
        try expectEqual(envelope.earlierExamples, EarlierExamplesCoverage.included(1))
        try expectTrue(envelope.items.count >= 2)
        try expectEqual(envelope.items[0].id, "new-turn", "recent examples lead the interleaved order")
        try expectEqual(envelope.items[1].id, "old-turn", "earlier examples alternate with recent ones")
        let oldItem = try require(envelope.items.first { $0.id == "old-turn" })
        try expectEqual(oldItem.observedAt, Date(timeIntervalSince1970: 1_767_230_400), "the earlier item carries its stored observed time")
        try expectEqual(envelope.items[0].observedAt, Date(timeIntervalSince1970: 1_767_600_400))
    }

    func missingEarlierContextIsExplicit() throws {
        let newer = makeSession(
            id: "session-only",
            turns: [makeTurn(id: "only-turn", sessionID: "session-only", role: .user, text: "Synthetic recent debugging session.", sequence: 0, at: Date(timeIntervalSince1970: 1_767_600_400), attribution: .unclear, note: "Observed role 'user'")],
            sourceSessionID: "src-only",
            startedAt: Date(timeIntervalSince1970: 1_767_600_400),
            missingIdentity: false
        )
        let persistence = makePersistence(Fixtures.makeTempDirectory("ctx-missing-earlier"), sessions: [newer])

        let envelope = try retrieve(persistence, terms: ["debugging"], comparison: true)

        try expectEqual(envelope.outcome, ContextOutcomeKind.historyIncluded)
        try expectEqual(envelope.earlierExamples, EarlierExamplesCoverage.missing)
        try expectTrue(
            envelope.uncertaintyNotes.contains { $0.contains("No earlier stored examples") },
            "the missing earlier side must be an explicit note"
        )
        try expectTrue(envelope.items.allSatisfy { $0.observedAt == Date(timeIntervalSince1970: 1_767_600_400) },
                       "no fabricated earlier example may appear")
    }

    func comparisonWithoutReliableTimesIsNotAssessable() throws {
        let turns = (0..<2).map { index in
            makeTurn(id: "undated-\(index)", sessionID: "session-undated", role: .user, text: "Synthetic undated debugging note \(index).", sequence: index, at: nil, attribution: .unclear, note: "Observed role 'user'")
        }
        let session = makeSession(id: "session-undated", turns: turns, sourceSessionID: "src-undated", startedAt: nil, missingIdentity: false)
        let persistence = makePersistence(Fixtures.makeTempDirectory("ctx-undated"), sessions: [session])

        let envelope = try retrieve(persistence, terms: ["debugging"], comparison: true)

        try expectEqual(envelope.earlierExamples, EarlierExamplesCoverage.notAssessable)
        try expectTrue(
            envelope.uncertaintyNotes.contains { $0.contains("not assessable") },
            "unknown times must make the comparison explicitly not assessable"
        )
        try expectTrue(envelope.items.allSatisfy { $0.timestampApproximate })
    }

    // MARK: Neighbor window

    func relevantNeighboringTurnsAreIncludedWithinBoundedWindow() throws {
        let base = Date(timeIntervalSince1970: 1_767_500_000)
        let turns = (0..<20).map { index -> ConversationTurn in
            let text = index == 10
                ? "Synthetic turn about debugging the fixture loader."
                : "Synthetic filler turn number \(index) with unrelated content."
            return makeTurn(
                id: "window-turn-\(index)",
                sessionID: "session-window",
                role: index % 2 == 0 ? .user : .assistant,
                text: text,
                sequence: index,
                at: base.addingTimeInterval(TimeInterval(index * 60)),
                attribution: index % 2 == 0 ? .unclear : .agent,
                note: "Observed role in synthetic fixture"
            )
        }
        let session = makeSession(id: "session-window", turns: turns, sourceSessionID: "src-window", startedAt: base, missingIdentity: false)
        let persistence = makePersistence(Fixtures.makeTempDirectory("ctx-window"), sessions: [session])

        let envelope = try retrieve(persistence, terms: ["debugging"])

        let turnItems = envelope.items.filter { $0.kind == .observedTurn }
        let sequences = turnItems.compactMap { item -> Int? in
            item.id.hasPrefix("window-turn-") ? Int(item.id.dropFirst("window-turn-".count)) : nil
        }.sorted()
        try expectEqual(sequences.count, 12, "the neighbor window is bounded by the turn cap")
        try expectEqual(sequences, Array(sequences.min()!...sequences.max()!), "the window is contiguous around the anchor")
        try expectTrue(sequences.contains(10), "the relevant anchor turn is included")
        try expectTrue(sequences.contains(9) && sequences.contains(11), "immediate neighbors are included")
        try expectTrue(sequences.min()! >= 4 && sequences.max()! <= 16, "the window stays near the anchor")
        try expectTrue(envelope.descriptor.coverage.includedTurnCount <= envelope.descriptor.budget.maxTurnCount)
    }

    // MARK: Caps and coverage accuracy

    func itemByteAndTurnCapsAreNeverExceeded() throws {
        let base = Date(timeIntervalSince1970: 1_767_500_000)
        var turns: [ConversationTurn] = []
        for sessionIndex in 0..<2 {
            for index in 0..<3 {
                turns.append(makeTurn(
                    id: "cap-\(sessionIndex)-\(index)",
                    sessionID: "cap-session-\(sessionIndex)",
                    role: .user,
                    text: "Synthetic alpha text \(sessionIndex)-\(index).",
                    sequence: index,
                    at: base.addingTimeInterval(TimeInterval((sessionIndex * 3 + index) * 60)),
                    attribution: .unclear,
                    note: "Observed role 'user'"
                ))
            }
        }
        let sessions = (0..<2).map { index in
            makeSession(
                id: "cap-session-\(index)",
                turns: Array(turns.filter { $0.sessionID == "cap-session-\(index)" }),
                sourceSessionID: "src-cap-\(index)",
                startedAt: base,
                missingIdentity: false
            )
        }
        let persistence = makePersistence(Fixtures.makeTempDirectory("ctx-caps"), sessions: sessions)
        let budget = try BoundedContextBudget(maxItemCount: 3, maxByteCount: 250, maxTurnCount: 2)

        let envelope = try retrieve(persistence, terms: ["alpha"], budget: budget)

        try expectTrue(envelope.items.count <= 3, "item cap")
        try expectTrue(envelope.descriptor.coverage.includedTurnCount <= 2, "turn cap")
        let byteSum = envelope.items.reduce(0) { $0 + $1.byteCount }
        try expectTrue(byteSum <= 250, "byte cap: \(byteSum)")
        for item in envelope.items {
            try expectEqual(item.byteCount, item.text.utf8.count, "counted bytes must be exact UTF-8 bytes")
        }
        try expectEqual(envelope.descriptor.coverage.state, SourceCoverageState.partial)
        try expectTrue(envelope.descriptor.coverage.omittedItemCount > 0)
    }

    func coverageCountsAndTruncationAreAccurate() throws {
        let base = Date(timeIntervalSince1970: 1_767_500_000)
        let filler = String(repeating: "Synthetic coverage sentence with é and 🧪 bytes. ", count: 6)
        let turns = (0..<4).map { index in
            makeTurn(
                id: "trunc-\(index)",
                sessionID: "trunc-session",
                role: .user,
                text: "Synthetic trimming candidate \(index): \(filler)",
                sequence: index,
                at: base.addingTimeInterval(TimeInterval(index * 60)),
                attribution: .unclear,
                note: "Observed role 'user'"
            )
        }
        let session = makeSession(id: "trunc-session", turns: turns, sourceSessionID: "src-trunc", startedAt: base, missingIdentity: false)
        let persistence = makePersistence(Fixtures.makeTempDirectory("ctx-truncation"), sessions: [session])
        let budget = try BoundedContextBudget(maxItemCount: 24, maxByteCount: 620, maxTurnCount: 12)

        let envelope = try retrieve(persistence, terms: ["trimming"], budget: budget)

        try expectEqual(envelope.items.count, 2, "one full item plus one truncated item fit the byte budget")
        try expectFalse(envelope.items[0].truncated)
        try expectTrue(envelope.items[1].truncated)
        try expectEqual(envelope.truncatedItemIDs, [envelope.items[1].id])
        try expectTrue(envelope.items[1].text.hasSuffix(" …[truncated]"), "truncation must be labeled")
        let totalRelevant = envelope.descriptor.coverage.includedItemCount + envelope.descriptor.coverage.omittedItemCount
        try expectEqual(totalRelevant, 4, "included plus omitted must account for every relevant item")
        let byteSum = envelope.items.reduce(0) { $0 + $1.byteCount }
        try expectEqual(envelope.descriptor.coverage.includedByteCount, byteSum)
        try expectTrue(byteSum <= 620)
        for item in envelope.items {
            try expectEqual(item.byteCount, item.text.utf8.count)
            try expectTrue(
                String(decoding: item.text.utf8, as: UTF8.self) == item.text,
                "truncation must stay on a UTF-8 character boundary even with multibyte content"
            )
        }
    }

    // MARK: Distinct provenance

    func correctionsAndSelfReportsCarryDistinctProvenance() throws {
        let event = makeEvent(id: "prov-event", summary: "Synthetic payment flow investigation.", at: Date(timeIntervalSince1970: 1_767_500_000))
        let correction = AttributionCorrection(eventId: "prov-event", attribution: .you, updatedAt: now)
        let report = makeReport(
            day: "2026-01-05",
            answers: ["2026-01-05-note": "I chose the retry approach because the fixture loop needed a backoff."],
            analysisResult: "ANALYSIS-RESULT-SENTINEL-XYZ",
            narrative: "NARRATIVE-SENTINEL-XYZ"
        )
        let persistence = makePersistence(
            Fixtures.makeTempDirectory("ctx-provenance"),
            events: [event],
            corrections: [correction],
            reports: [report]
        )

        let envelope = try retrieve(persistence, terms: ["payment", "retry"])
        let document = String(decoding: ContextSerializer().providerDocument(for: envelope), as: UTF8.self)

        try expectEqual(envelope.outcome, ContextOutcomeKind.historyIncluded)
        let observed = try require(envelope.items.first { $0.id == "prov-event" })
        try expectEqual(observed.kind, ContextItem.Kind.observedEvent)
        try expectEqual(observed.provenance, ClaimProvenance.observed)
        try expectEqual(observed.observedAttribution, Attribution.unclear, "the observation must keep its original attribution")

        let corrected = try require(envelope.items.first { $0.kind == .userCorrection })
        try expectEqual(corrected.provenance, ClaimProvenance.userCorrection)
        try expectEqual(corrected.sourceRecordID, "prov-event")
        try expectFalse(corrected.id == observed.id, "the correction is a separate item")

        let selfReport = try require(envelope.items.first { $0.kind == .selfReport })
        try expectEqual(selfReport.provenance, ClaimProvenance.selfReport)
        try expectEqual(selfReport.dayKey, "2026-01-05")
        try expectTrue(selfReport.text.contains("retry approach"))

        try expectFalse(document.contains("ANALYSIS-RESULT-SENTINEL-XYZ"), "generated analysis output must never be promoted into context")
        try expectFalse(document.contains("NARRATIVE-SENTINEL-XYZ"), "generated narrative must never be promoted into context")
        try expectFalse(envelope.items.contains { $0.text.contains("SENTINEL") })
    }

    // MARK: Store state distinguishability

    func missingStoreIsDistinguishableFromEmptyAndNoMatch() throws {
        let fresh = PersistenceController(directory: Fixtures.makeTempDirectory("ctx-missing-stores"))
        let retriever = ContextRetriever(persistence: fresh)

        let envelope = try retriever.retrieve(ContextRetrievalRequest(terms: ["anything"]), now: now)
        try expectEqual(envelope.outcome, ContextOutcomeKind.noRelevantHistory)
        try expectEqual(
            envelope.missingStores,
            [.corrections, .events, .reports, .sessions],
            "an absent store is reported, not treated as damaged or as history"
        )
        try expectEqual(envelope.descriptor.coverage.state, SourceCoverageState.complete)
        try expectTrue(envelope.uncertaintyNotes.contains { $0.contains("do not exist yet") })

        try fresh.saveSessions([])
        let afterEmptySessionsSave = try retriever.retrieve(ContextRetrievalRequest(terms: ["anything"]), now: now)
        try expectFalse(afterEmptySessionsSave.missingStores.contains(.sessions), "a present-but-empty store is not 'missing'")
        try expectEqual(afterEmptySessionsSave.outcome, ContextOutcomeKind.noRelevantHistory)
    }

    func damagedStoreFailsClosed() throws {
        let directory = Fixtures.makeTempDirectory("ctx-damaged-events")
        try Data("{\"synthetic-damaged-events-fixture\":".utf8).write(to: directory.appendingPathComponent("events.json"))
        let persistence = PersistenceController(directory: directory)
        let retriever = ContextRetriever(persistence: persistence)

        do {
            _ = try retriever.retrieve(ContextRetrievalRequest(terms: ["anything"]), now: now)
            throw TestFailure("retrieval must fail closed on a damaged events store")
        } catch let failure as ContextRetrievalFailure {
            guard case .storeDamaged(let store, let message) = failure else {
                throw TestFailure("unexpected failure kind: \(failure)")
            }
            try expectEqual(store, StoreName.events)
            try expectFalse(message.isEmpty)
            try expectFalse(message.contains(directory.path), "the failure must not expose private paths")
        }
        try expectEqual(
            try Data(contentsOf: directory.appendingPathComponent("events.json")),
            Data("{\"synthetic-damaged-events-fixture\":".utf8),
            "the damaged store must stay byte-for-byte untouched"
        )

        let sessionsDirectory = Fixtures.makeTempDirectory("ctx-damaged-sessions")
        try Data("not json at all".utf8).write(to: sessionsDirectory.appendingPathComponent("sessions.json"))
        let sessionsPersistence = PersistenceController(directory: sessionsDirectory)
        do {
            _ = try ContextRetriever(persistence: sessionsPersistence).retrieve(ContextRetrievalRequest(terms: ["anything"]), now: now)
            throw TestFailure("retrieval must fail closed on a damaged sessions store")
        } catch let failure as ContextRetrievalFailure {
            guard case .storeDamaged(let store, _) = failure else {
                throw TestFailure("unexpected failure kind: \(failure)")
            }
            try expectEqual(store, StoreName.sessions)
        }
    }

    func noRelevantHistoryIsDistinctFromRelevantHistoryExcluded() throws {
        let cleanSession = makeSession(
            id: "session-clean",
            turns: [makeTurn(id: "clean-turn", sessionID: "session-clean", role: .user, text: "Synthetic unrelated note about gardening.", sequence: 0, at: now, attribution: .unclear, note: "Observed role 'user'")],
            sourceSessionID: "src-clean",
            startedAt: now,
            missingIdentity: false
        )
        let persistence = makePersistence(Fixtures.makeTempDirectory("ctx-no-match"), sessions: [cleanSession])
        let noMatch = try retrieve(persistence, terms: ["debugging"])
        try expectEqual(noMatch.outcome, ContextOutcomeKind.noRelevantHistory)
        try expectEqual(noMatch.descriptor.coverage.omittedItemCount, 0)

        let secretText = "Synthetic debugging note with Bearer \(String(repeating: "aBc9xY2z", count: 5)) token."
        let secretSession = makeSession(
            id: "session-secret",
            turns: [makeTurn(id: "secret-turn", sessionID: "session-secret", role: .user, text: secretText, sequence: 0, at: now, attribution: .unclear, note: "Observed role 'user'")],
            sourceSessionID: "src-secret",
            startedAt: now,
            missingIdentity: false
        )
        let secretPersistence = makePersistence(Fixtures.makeTempDirectory("ctx-excluded"), sessions: [secretSession])
        let excluded = try retrieve(secretPersistence, terms: ["debugging"])
        try expectEqual(excluded.outcome, ContextOutcomeKind.relevantHistoryExcluded)
        try expectTrue(excluded.descriptor.coverage.omittedItemCount > 0)
        try expectTrue(excluded.uncertaintyNotes.contains { $0.contains("secret-shaped") })
    }

    // MARK: Stored-data-only retrieval

    func repeatedRetrievalUsesOnlyStoredDataEvenWhenSourceChangesOrDeletes() throws {
        let file = writeSessionFixture(name: "storedonly")
        let originalBytes = try Data(contentsOf: file)
        let persistence = PersistenceController(directory: Fixtures.makeTempDirectory("ctx-storedonly-store"))
        _ = SessionImportService(persistence: persistence).importCodexSessionFile(at: file, now: now)

        let retriever = ContextRetriever(persistence: persistence)
        let first = try retriever.retrieve(ContextRetrievalRequest(terms: ["fixture"]), now: now)
        let firstDocument = ContextSerializer().providerDocument(for: first)
        try expectEqual(try Data(contentsOf: file), originalBytes, "retrieval must not modify the source file")

        var appended = originalBytes
        appended.append(Data("\n".utf8))
        appended.append(Data(#"{"type":"event_msg","payload":{"type":"token_count"}}"#.utf8))
        try appended.write(to: file)
        let second = try retriever.retrieve(ContextRetrievalRequest(terms: ["fixture"]), now: now)
        try expectEqual(second, first, "appending to the source without re-import changes nothing")

        try FileManager.default.removeItem(at: file)
        let third = try retriever.retrieve(ContextRetrievalRequest(terms: ["fixture"]), now: now)
        try expectEqual(third, first, "deleting the source must not change stored-data retrieval")
        try expectEqual(ContextSerializer().providerDocument(for: third), firstDocument, "serialized bytes stay stable without any source")
    }

    // MARK: Ambiguity and missing metadata

    func userRoleTurnsRemainAmbiguousInRetrievedContext() throws {
        let turns = [
            makeTurn(id: "amb-user", sessionID: "session-amb", role: .user, text: "Synthetic user-role record that could carry injected context.", sequence: 0, at: now, attribution: .unclear, note: "Observed role 'user'; user-role records can also carry tool-injected context, so this is not asserted as human authorship"),
            makeTurn(id: "amb-agent", sessionID: "session-amb", role: .assistant, text: "Synthetic assistant reply.", sequence: 1, at: now.addingTimeInterval(60), attribution: .agent, note: "Observed role 'assistant'")
        ]
        let session = makeSession(id: "session-amb", turns: turns, sourceSessionID: "src-amb", startedAt: now, missingIdentity: false)
        let persistence = makePersistence(Fixtures.makeTempDirectory("ctx-ambiguity"), sessions: [session])

        let envelope = try retrieve(persistence, terms: [])
        let document = String(decoding: ContextSerializer().providerDocument(for: envelope), as: UTF8.self)

        let userItem = try require(envelope.items.first { $0.id == "amb-user" })
        try expectEqual(userItem.observedAttribution, Attribution.unclear, "user-role ambiguity must survive retrieval")
        let agentItem = try require(envelope.items.first { $0.id == "amb-agent" })
        try expectEqual(agentItem.observedAttribution, Attribution.agent)
        try expectTrue(document.contains("does not prove human authorship"), "the serialized label must preserve ambiguity")
        try expectTrue(document.contains("attribution: Unclear"), "the unclear label must reach the provider text")
    }

    func missingMetadataIsReportedHonestly() throws {
        let turns = [
            makeTurn(id: "meta-untimed", sessionID: "session-meta", role: .user, text: "Synthetic debugging record without a timestamp.", sequence: 0, at: nil, attribution: .unclear, note: "Observed role 'user'")
        ]
        let session = makeSession(id: "session-meta", turns: turns, sourceSessionID: nil, startedAt: nil, missingIdentity: true)
        let persistence = makePersistence(Fixtures.makeTempDirectory("ctx-metadata"), sessions: [session])

        let envelope = try retrieve(persistence, terms: ["debugging"])

        let item = try require(envelope.items.first { $0.id == "meta-untimed" })
        try expectNil(item.observedAt, "a missing observed time stays missing")
        try expectTrue(item.timestampApproximate)
        try expectEqual(envelope.dateCoverage.earliest, nil)
        try expectEqual(envelope.dateCoverage.latest, nil)
        try expectTrue(envelope.dateCoverage.includesApproximateOrMissingTimes)
        try expectTrue(envelope.uncertaintyNotes.contains { $0.contains("no observed time") })
        try expectTrue(envelope.uncertaintyNotes.contains { $0.contains("no source-provided session identity") })
    }

    // MARK: Session fixture helper (source files are never re-read by retrieval)

    private func writeSessionFixture(name: String) -> URL {
        let dir = Fixtures.makeTempDirectory("ctx-fixture-\(name)")
        let file = dir.appendingPathComponent("rollout-fixture-\(name).jsonl")
        let lines = [
            #"{"timestamp":"2026-01-05T09:00:00Z","type":"session_meta","payload":{"id":"fixture-session-context"}}"#,
            #"{"timestamp":"2026-01-05T09:00:05Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Synthetic fixture text about debugging for stored-only retrieval."}]}}"#
        ]
        Fixtures.write(lines.joined(separator: "\n") + "\n", to: file)
        return file
    }

    static var entries: [TestEntry] {
        let tests = ContextRetrievalTests()
        return [
            TestEntry(suite: suiteName, name: "comparisonSelectsEarlierAndRecentExamples") {
                try tests.comparisonSelectsEarlierAndRecentExamples()
            },
            TestEntry(suite: suiteName, name: "missingEarlierContextIsExplicit") {
                try tests.missingEarlierContextIsExplicit()
            },
            TestEntry(suite: suiteName, name: "comparisonWithoutReliableTimesIsNotAssessable") {
                try tests.comparisonWithoutReliableTimesIsNotAssessable()
            },
            TestEntry(suite: suiteName, name: "relevantNeighboringTurnsAreIncludedWithinBoundedWindow") {
                try tests.relevantNeighboringTurnsAreIncludedWithinBoundedWindow()
            },
            TestEntry(suite: suiteName, name: "itemByteAndTurnCapsAreNeverExceeded") {
                try tests.itemByteAndTurnCapsAreNeverExceeded()
            },
            TestEntry(suite: suiteName, name: "coverageCountsAndTruncationAreAccurate") {
                try tests.coverageCountsAndTruncationAreAccurate()
            },
            TestEntry(suite: suiteName, name: "correctionsAndSelfReportsCarryDistinctProvenance") {
                try tests.correctionsAndSelfReportsCarryDistinctProvenance()
            },
            TestEntry(suite: suiteName, name: "missingStoreIsDistinguishableFromEmptyAndNoMatch") {
                try tests.missingStoreIsDistinguishableFromEmptyAndNoMatch()
            },
            TestEntry(suite: suiteName, name: "damagedStoreFailsClosed") {
                try tests.damagedStoreFailsClosed()
            },
            TestEntry(suite: suiteName, name: "noRelevantHistoryIsDistinctFromRelevantHistoryExcluded") {
                try tests.noRelevantHistoryIsDistinctFromRelevantHistoryExcluded()
            },
            TestEntry(suite: suiteName, name: "repeatedRetrievalUsesOnlyStoredDataEvenWhenSourceChangesOrDeletes") {
                try tests.repeatedRetrievalUsesOnlyStoredDataEvenWhenSourceChangesOrDeletes()
            },
            TestEntry(suite: suiteName, name: "userRoleTurnsRemainAmbiguousInRetrievedContext") {
                try tests.userRoleTurnsRemainAmbiguousInRetrievedContext()
            },
            TestEntry(suite: suiteName, name: "missingMetadataIsReportedHonestly") {
                try tests.missingMetadataIsReportedHonestly()
            }
        ]
    }
}
