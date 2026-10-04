import Foundation
@testable import ReflectLib

/// M2 slice 2 privacy coverage for bounded context retrieval: secret-shaped
/// content never reaches an envelope or provider-bound document (synthetic
/// sentinels only), source paths never enter provider text, item text quoting
/// a private locator is omitted, serialized output is deterministic, raw
/// stored evidence stays unchanged, and retained context stays separate from
/// local display previews. No provider is invoked and no real secret, path,
/// or history is used anywhere.
struct ContextPrivacyTests {
    static let suiteName = "ContextPrivacyTests"

    private let now = Date(timeIntervalSince1970: 1_767_614_400) // 2026-01-05T12:00:00Z

    // MARK: Synthetic sentinels (fictional shapes only)

    private var bearerSentinel: String { "Bearer \(String(repeating: "sYn9Th3t", count: 6))" }
    private var skKeySentinel: String { "sk-" + String(repeating: "xY3sYnZ9", count: 3) }
    private var privateKeySentinel: String { "-----BEGIN RSA PRIVATE KEY-----\nZm1peGVkc2VudGluZWw=\n-----END RSA PRIVATE KEY-----" }
    private var awsKeySentinel: String { "AKIA" + "IOSFODNN7" + "EXAMPLE" }
    private var githubSentinel: String { "ghp_" + String(repeating: "sYn0Th3t", count: 5) }
    private var slackSentinel: String { "xoxb-" + String(repeating: "1234567890", count: 3) + "-synthetic" }

    private func turn(id: String, sessionID: String, text: String, sequence: Int, at: Date?, path: String = "/tmp/synthetic/privacy.jsonl") -> ConversationTurn {
        let revision = TurnRevision(
            revisionID: "rev-\(id)",
            importedAt: now,
            timestamp: at,
            timestampApproximate: at == nil,
            retainedText: text,
            retainedTextTruncated: false,
            localPreview: String(text.prefix(12)),
            previewTruncated: text.count > 12
        )
        return ConversationTurn(
            id: id,
            sessionID: sessionID,
            role: .user,
            sourceTurnID: nil,
            sourcePath: path,
            sourceLine: sequence + 2,
            sequence: sequence,
            observedAttribution: .unclear,
            observedAttributionNote: "Observed role 'user'",
            revisions: [revision]
        )
    }

    private func session(id: String, turns: [ConversationTurn]) -> WorkSession {
        let timestamps = turns.compactMap { $0.revisions.last?.timestamp }
        return WorkSession(
            id: id,
            sourceKind: .codex,
            sourceSessionID: "src-\(id)",
            title: nil,
            project: nil,
            importRevision: 1,
            firstImportedAt: now,
            lastImportedAt: now,
            startedAt: timestamps.min(),
            startedAtApproximate: false,
            lastActivityAt: timestamps.max(),
            turns: turns,
            coverage: CoverageSummary(
                turnCount: turns.count,
                approximateTimestampTurnCount: 0,
                truncatedRetainedTextTurnCount: 0,
                missingSessionIdentity: false,
                firstRecordedAt: timestamps.min(),
                lastRecordedAt: timestamps.max(),
                parserVersion: "codex-sessions/1",
                parserUncertaintyNotes: []
            )
        )
    }

    private func document(for envelope: ContextEnvelope) -> String {
        String(decoding: ContextSerializer().providerDocument(for: envelope), as: UTF8.self)
    }

    // MARK: Secret-shaped strings

    func secretShapedItemsNeverEnterEnvelopeOrDocument() throws {
        let turns = [
            turn(id: "clean-turn", sessionID: "session-secrets", text: "Synthetic clean debugging note about the fixture loader.", sequence: 0, at: now),
            turn(id: "bearer-turn", sessionID: "session-secrets", text: "Use \(bearerSentinel) for the synthetic call.", sequence: 1, at: now),
            turn(id: "skkey-turn", sessionID: "session-secrets", text: "The key is \(skKeySentinel) in this synthetic note.", sequence: 2, at: now),
            turn(id: "pemkey-turn", sessionID: "session-secrets", text: "Synthetic private key block:\n\(privateKeySentinel)", sequence: 3, at: now),
            turn(id: "aws-turn", sessionID: "session-secrets", text: "Synthetic AWS key \(awsKeySentinel) inside text.", sequence: 4, at: now),
            turn(id: "github-turn", sessionID: "session-secrets", text: "Synthetic GitHub token \(githubSentinel) inside text.", sequence: 5, at: now)
        ]
        let report = DailyReport(
            day: "2026-01-05",
            narrative: "",
            narrativeGeneratedAt: nil,
            answers: ["2026-01-05-note": AnswerEntry(text: "Synthetic note with \(slackSentinel) inside.", updatedAt: now)],
            analysisResult: nil,
            analysisGeneratedAt: nil,
            updatedAt: now
        )
        let persistence = PersistenceController(directory: Fixtures.makeTempDirectory("ctx-privacy-secrets"))
        try persistence.saveSessions([session(id: "session-secrets", turns: turns)])
        try persistence.saveReports([report])

        let retriever = ContextRetriever(persistence: persistence)
        let envelope = try retriever.retrieve(ContextRetrievalRequest(terms: ["synthetic", "fixture"]), now: now)
        let rendered = document(for: envelope)

        try expectEqual(envelope.outcome, ContextOutcomeKind.historyIncluded, "the clean item is still includable")
        try expectTrue(envelope.items.map(\.id) == ["clean-turn"], "only the clean observation survives screening")

        let expectedSecretIDs = ["bearer-turn", "skkey-turn", "pemkey-turn", "aws-turn", "github-turn", "selfreport|2026-01-05|2026-01-05-note"]
        for id in expectedSecretIDs {
            try expectFalse(envelope.items.contains { $0.id == id }, "\(id) must never become an included item")
            try expectTrue(envelope.omittedItemIDs.contains(id), "\(id) must be reported as omitted")
        }
        for sentinel in [bearerSentinel, skKeySentinel, privateKeySentinel, awsKeySentinel, githubSentinel, slackSentinel] {
            try expectFalse(rendered.contains(sentinel), "the provider document must not contain the sentinel")
        }
        try expectTrue(
            envelope.uncertaintyNotes.contains { $0.contains("secret-shaped") },
            "the exclusion must be disclosed as a count, without payload"
        )

        let stored = try persistence.loadSessions()
        let storedTexts = stored.flatMap { $0.turns.map(\.retainedText) }
        try expectTrue(storedTexts.contains { $0.contains(bearerSentinel) }, "raw stored evidence stays unchanged locally")
    }

    // MARK: Source path exclusion

    func sourcePathsNeverEnterProviderText() throws {
        let fixturePath = writeSessionFixture(name: "pathsentinel")
        let persistence = PersistenceController(directory: Fixtures.makeTempDirectory("ctx-privacy-path-store"))
        _ = SessionImportService(persistence: persistence).importCodexSessionFile(at: fixturePath, now: now)
        let eventPath = Fixtures.makeTempDirectory("ctx-privacy-event-src").appendingPathComponent("event-source.jsonl").path
        let event = EvidenceEvent(
            id: "path-event",
            sourceKind: .copilotCLI,
            sourceName: "Copilot CLI",
            timestamp: now,
            timestampApproximate: false,
            kind: .userMessage,
            summary: "Synthetic event for path exclusion checks.",
            detail: "",
            evidencePath: eventPath,
            evidenceLine: 9,
            observedAttribution: .unclear,
            observedAttributionNote: "Observed role in synthetic fixture",
            importedAt: now
        )
        try persistence.saveEvents([event])

        let retriever = ContextRetriever(persistence: persistence)
        let envelope = try retriever.retrieve(ContextRetrievalRequest(terms: ["synthetic", "fixture"]), now: now)
        let rendered = document(for: envelope)

        try expectFalse(rendered.contains(fixturePath.path), "the source file path must never reach provider text")
        try expectFalse(rendered.contains(eventPath), "the event locator path must never reach provider text")
        for item in envelope.items {
            try expectFalse(item.text.contains(fixturePath.path))
            try expectFalse(item.text.contains(eventPath))
            try expectFalse(item.text.contains("sourceLine"), "line locators are never serialized")
        }
        try expectTrue(envelope.items.contains { $0.id == "path-event" })
    }

    func itemTextQuotingAPrivateLocatorIsOmitted() throws {
        let privatePath = Fixtures.makeTempDirectory("ctx-privacy-quoted-src").appendingPathComponent("rollout-secret-location.jsonl").path
        let turns = [
            turn(id: "safe-turn", sessionID: "session-quoted", text: "Synthetic clean note without any locator.", sequence: 0, at: now, path: privatePath),
            turn(id: "quoted-turn", sessionID: "session-quoted", text: "See the notes at \(privatePath) for the synthetic details.", sequence: 1, at: now, path: privatePath)
        ]
        let persistence = PersistenceController(directory: Fixtures.makeTempDirectory("ctx-privacy-quoted-store"))
        try persistence.saveSessions([session(id: "session-quoted", turns: turns)])

        let retriever = ContextRetriever(persistence: persistence)
        let envelope = try retriever.retrieve(ContextRetrievalRequest(terms: ["synthetic"]), now: now)
        let rendered = document(for: envelope)

        try expectEqual(envelope.items.map(\.id), ["safe-turn"])
        try expectTrue(envelope.omittedItemIDs.contains("quoted-turn"))
        try expectTrue(envelope.uncertaintyNotes.contains { $0.contains("private source locations") })
        try expectFalse(rendered.contains(privatePath))
    }

    /// Cross-record screening: every candidate is checked against all known
    /// private locators from the loaded stores, so a different stored turn
    /// and a saved answer quoting another imported record's exact source
    /// path are omitted, the quoted paths never reach items or the provider
    /// document, and clean items stay includable. Raw stored fixtures stay
    /// unchanged. All locators are fictional /tmp/synthetic values.
    func crossRecordLocatorQuotingIsScreenedAgainstAllStoredLocators() throws {
        let ownerPath = "/tmp/synthetic/rollout-owner.jsonl"
        let quoterPath = "/tmp/synthetic/rollout-quoter.jsonl"
        let eventPath = "/tmp/synthetic/event-source-quoted.jsonl"

        let ownerSession = session(id: "session-owner", turns: [
            turn(id: "owner-clean", sessionID: "session-owner", text: "Synthetic clean owner note for cross-record screening.", sequence: 0, at: now, path: ownerPath)
        ])
        let quoterSession = session(id: "session-quoter", turns: [
            turn(id: "quoter-quotes-owner", sessionID: "session-quoter", text: "Synthetic cross record quoting \(ownerPath) for the details.", sequence: 0, at: now, path: quoterPath),
            turn(id: "quoter-quotes-event", sessionID: "session-quoter", text: "Synthetic cross record referencing \(eventPath).", sequence: 1, at: now, path: quoterPath),
            turn(id: "quoter-clean", sessionID: "session-quoter", text: "Synthetic clean quoter note without any locator.", sequence: 2, at: now, path: quoterPath)
        ])
        let quotedEvent = EvidenceEvent(
            id: "event-quoted",
            sourceKind: .copilotCLI,
            sourceName: "Copilot CLI",
            timestamp: now,
            timestampApproximate: false,
            kind: .userMessage,
            summary: "Synthetic clean event for cross-record screening.",
            detail: "",
            evidencePath: eventPath,
            evidenceLine: 4,
            observedAttribution: .unclear,
            observedAttributionNote: "Observed role in synthetic fixture",
            importedAt: now
        )
        let report = DailyReport(
            day: "2026-01-05",
            narrative: "",
            narrativeGeneratedAt: nil,
            answers: [
                "2026-01-05-note": AnswerEntry(text: "Synthetic answer quoting \(ownerPath) inside.", updatedAt: now),
                "2026-01-05-clean": AnswerEntry(text: "Synthetic clean answer for includability.", updatedAt: now)
            ],
            analysisResult: nil,
            analysisGeneratedAt: nil,
            updatedAt: now
        )
        let savedSessions = [ownerSession, quoterSession]
        let savedEvents = [quotedEvent]
        let persistence = PersistenceController(directory: Fixtures.makeTempDirectory("ctx-privacy-cross-store"))
        try persistence.saveSessions(savedSessions)
        try persistence.saveEvents(savedEvents)
        try persistence.saveReports([report])

        let retriever = ContextRetriever(persistence: persistence)
        let envelope = try retriever.retrieve(ContextRetrievalRequest(terms: ["synthetic"]), now: now)
        let rendered = document(for: envelope)

        let includedIDs = Set(envelope.items.map(\.id))
        try expectTrue(includedIDs == ["owner-clean", "quoter-clean", "event-quoted", "selfreport|2026-01-05|2026-01-05-clean"],
                       "clean items must stay includable: \(includedIDs)")
        for excluded in ["quoter-quotes-owner", "quoter-quotes-event", "selfreport|2026-01-05|2026-01-05-note"] {
            try expectFalse(includedIDs.contains(excluded), "\(excluded) must be omitted")
            try expectTrue(envelope.omittedItemIDs.contains(excluded), "\(excluded) must be reported as omitted")
        }
        for locator in [ownerPath, quoterPath, eventPath] {
            try expectFalse(rendered.contains(locator), "the provider document must not contain \(locator)")
            for item in envelope.items {
                try expectFalse(item.text.contains(locator), "no envelope item may contain \(locator)")
            }
        }
        try expectTrue(
            envelope.uncertaintyNotes.contains { $0.contains("private source locations") },
            "the cross-record omissions must be disclosed as counts, without paths"
        )

        try expectEqual(try persistence.loadSessions(), savedSessions, "raw stored sessions stay unchanged")
        try expectEqual(try persistence.loadEvents(), savedEvents, "raw stored events stay unchanged")
    }

    // MARK: Determinism and separation

    func serializedOutputIsDeterministic() throws {
        let turns = [
            turn(id: "det-a", sessionID: "session-det", text: "Synthetic deterministic note alpha.", sequence: 0, at: now),
            turn(id: "det-b", sessionID: "session-det", text: "Synthetic deterministic note beta.", sequence: 1, at: now.addingTimeInterval(60))
        ]
        let persistence = PersistenceController(directory: Fixtures.makeTempDirectory("ctx-privacy-det-store"))
        try persistence.saveSessions([session(id: "session-det", turns: turns)])

        let retriever = ContextRetriever(persistence: persistence)
        let first = try retriever.retrieve(ContextRetrievalRequest(terms: ["deterministic"]), now: now)
        let second = try retriever.retrieve(ContextRetrievalRequest(terms: ["deterministic"]), now: now)
        try expectEqual(second, first)
        try expectEqual(
            ContextSerializer().providerDocument(for: second),
            ContextSerializer().providerDocument(for: first),
            "identical stores, request, and clock produce byte-identical provider text"
        )
    }

    func retainedContextStaysSeparateFromLocalPreview() throws {
        let longText = String(repeating: "Synthetic retained context sentence for separation checks. ", count: 8)
        let revision = TurnRevision(
            revisionID: "rev-preview",
            importedAt: now,
            timestamp: now,
            timestampApproximate: false,
            retainedText: longText,
            retainedTextTruncated: false,
            localPreview: String(longText.prefix(60)) + "…",
            previewTruncated: true
        )
        let importedTurn = ConversationTurn(
            id: "preview-turn",
            sessionID: "session-preview",
            role: .user,
            sourceTurnID: nil,
            sourcePath: "/tmp/synthetic/preview.jsonl",
            sourceLine: 2,
            sequence: 0,
            observedAttribution: .unclear,
            observedAttributionNote: "Observed role 'user'",
            revisions: [revision]
        )
        let persistence = PersistenceController(directory: Fixtures.makeTempDirectory("ctx-privacy-preview-store"))
        try persistence.saveSessions([session(id: "session-preview", turns: [importedTurn])])

        let retriever = ContextRetriever(persistence: persistence)
        let envelope = try retriever.retrieve(ContextRetrievalRequest(terms: ["retained"]), now: now)
        let rendered = document(for: envelope)

        let item = try require(envelope.items.first)
        try expectTrue(item.text.contains(longText), "provider-bound context uses the full retained text")
        try expectFalse(rendered.contains(revision.localPreview), "the short display preview never replaces retained context")
        try expectTrue(revision.localPreview.count < longText.count)
    }

    // MARK: Fixture helper

    @discardableResult
    private func writeSessionFixture(name: String) -> URL {
        let dir = Fixtures.makeTempDirectory("ctx-privacy-\(name)")
        let file = dir.appendingPathComponent("rollout-fixture-\(name).jsonl")
        let lines = [
            #"{"timestamp":"2026-01-05T09:00:00Z","type":"session_meta","payload":{"id":"fixture-session-privacy"}}"#,
            #"{"timestamp":"2026-01-05T09:00:05Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Synthetic fixture note for path exclusion checks."}]}}"#
        ]
        Fixtures.write(lines.joined(separator: "\n") + "\n", to: file)
        return file
    }

    static var entries: [TestEntry] {
        let tests = ContextPrivacyTests()
        return [
            TestEntry(suite: suiteName, name: "secretShapedItemsNeverEnterEnvelopeOrDocument") {
                try tests.secretShapedItemsNeverEnterEnvelopeOrDocument()
            },
            TestEntry(suite: suiteName, name: "sourcePathsNeverEnterProviderText") {
                try tests.sourcePathsNeverEnterProviderText()
            },
            TestEntry(suite: suiteName, name: "itemTextQuotingAPrivateLocatorIsOmitted") {
                try tests.itemTextQuotingAPrivateLocatorIsOmitted()
            },
            TestEntry(suite: suiteName, name: "crossRecordLocatorQuotingIsScreenedAgainstAllStoredLocators") {
                try tests.crossRecordLocatorQuotingIsScreenedAgainstAllStoredLocators()
            },
            TestEntry(suite: suiteName, name: "serializedOutputIsDeterministic") {
                try tests.serializedOutputIsDeterministic()
            },
            TestEntry(suite: suiteName, name: "retainedContextStaysSeparateFromLocalPreview") {
                try tests.retainedContextStaysSeparateFromLocalPreview()
            }
        ]
    }
}
