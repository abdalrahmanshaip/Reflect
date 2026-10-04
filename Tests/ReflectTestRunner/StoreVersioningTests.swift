import Foundation
@testable import ReflectLib

/// M1b1 coverage for the versioned per-file JSON store envelope: every store
/// saves deterministic version-1 envelopes, legacy bare payloads (schema
/// version 0) keep reading exactly without write-on-read and stay read-only
/// until the explicit migration exists (ordinary saves over them are typed
/// rejections), and corrupt, wrong-store, or newer-version files are rejected
/// fail-closed with their bytes untouched. Every fixture is synthetic and
/// lives in a fresh temporary directory; no real user data is ever read.
struct StoreVersioningTests {
    static let suiteName = "StoreVersioningTests"

    private let referenceDate = Date(timeIntervalSince1970: 1_767_614_400)

    // MARK: Synthetic full payloads

    private func syntheticEvent(id: String) -> EvidenceEvent {
        EvidenceEvent(
            id: id,
            sourceKind: .claudeCode,
            sourceName: "Claude Code",
            timestamp: referenceDate,
            timestampApproximate: true,
            kind: .userMessage,
            summary: "Synthetic event \(id)",
            detail: "Synthetic preview text for the fixture event",
            evidencePath: "/tmp/fixture/session.jsonl",
            evidenceLine: 42,
            observedAttribution: .unclear,
            observedAttributionNote: "Structural role in transcript",
            importedAt: referenceDate
        )
    }

    /// Per-store fixture bundle: full synthetic payload, its legacy bare JSON
    /// (schema version 0), and typed save/load probes. Legacy JSON matches
    /// exactly what earlier Reflect builds wrote on this toolchain, including
    /// enum-keyed dictionaries encoded as alternating key/value arrays.
    private struct StoreFixture {
        let store: StoreName
        let legacyJSON: String
        let barePayloadJSON: () throws -> String
        let save: (PersistenceController) throws -> Void
        let loadIgnoringResult: (PersistenceController) throws -> Void
        let assertLoaded: (PersistenceController) throws -> Void
        let assertLegacyLoaded: (PersistenceController) throws -> Void
        let assertHealthLoaded: (PersistenceController) throws -> Void
        let assertLegacyHealthLoaded: (PersistenceController) throws -> Void
    }

    private func makeFixture(_ store: StoreName) -> StoreFixture {
        switch store {
        case .events:
            let events = [syntheticEvent(id: "fixture-event-1"), syntheticEvent(id: "fixture-event-2")]
            let legacy = """
            [
              {
                "detail" : "Synthetic preview text for the fixture event",
                "evidenceLine" : 42,
                "evidencePath" : "/tmp/fixture/session.jsonl",
                "id" : "fixture-event-1",
                "importedAt" : "2026-01-05T12:00:00Z",
                "kind" : "user_message",
                "observedAttribution" : "unclear",
                "observedAttributionNote" : "Structural role in transcript",
                "sourceKind" : "claude_code",
                "sourceName" : "Claude Code",
                "summary" : "Synthetic event fixture-event-1",
                "timestamp" : "2026-01-05T12:00:00Z",
                "timestampApproximate" : true
              }
            ]
            """
            return StoreFixture(
                store: .events,
                legacyJSON: legacy,
                barePayloadJSON: { try self.compactPayloadJSON(events) },
                save: { try $0.saveEvents(events) },
                loadIgnoringResult: { _ = try $0.loadEvents() },
                assertLoaded: { try expectEqual(try $0.loadEvents(), events) },
                assertLegacyLoaded: { persistence in
                    try expectEqual(try persistence.loadEvents(), [events[0]], "the legacy file holds exactly its one synthetic event")
                },
                assertHealthLoaded: { persistence in
                    guard case .loaded(let value) = persistence.loadEventsHealth() else {
                        throw TestFailure("events: expected a loaded store")
                    }
                    try expectEqual(value, events)
                },
                assertLegacyHealthLoaded: { persistence in
                    guard case .loaded(let value) = persistence.loadEventsHealth() else {
                        throw TestFailure("events: expected a loaded legacy store")
                    }
                    try expectEqual(value, [events[0]], "the legacy file holds exactly its one synthetic event")
                }
            )
        case .corrections:
            let corrections = [
                AttributionCorrection(eventId: "fixture-event-1", attribution: .you, updatedAt: referenceDate),
                AttributionCorrection(eventId: "fixture-event-2", attribution: .agent, updatedAt: referenceDate)
            ]
            let legacy = """
            [
              {
                "attribution" : "you",
                "eventId" : "fixture-event-1",
                "updatedAt" : "2026-01-05T12:00:00Z"
              },
              {
                "attribution" : "agent",
                "eventId" : "fixture-event-2",
                "updatedAt" : "2026-01-05T12:00:00Z"
              }
            ]
            """
            return StoreFixture(
                store: .corrections,
                legacyJSON: legacy,
                barePayloadJSON: { try self.compactPayloadJSON(corrections) },
                save: { try $0.saveCorrections(corrections) },
                loadIgnoringResult: { _ = try $0.loadCorrections() },
                assertLoaded: { try expectEqual(try $0.loadCorrections(), corrections) },
                assertLegacyLoaded: { try expectEqual(try $0.loadCorrections(), corrections) },
                assertHealthLoaded: { persistence in
                    guard case .loaded(let value) = persistence.loadCorrectionsHealth() else {
                        throw TestFailure("corrections: expected a loaded store")
                    }
                    try expectEqual(value, corrections)
                },
                assertLegacyHealthLoaded: { persistence in
                    guard case .loaded(let value) = persistence.loadCorrectionsHealth() else {
                        throw TestFailure("corrections: expected a loaded legacy store")
                    }
                    try expectEqual(value, corrections)
                }
            )
        case .reports:
            var answered = DailyReport(
                day: "2026-01-05",
                narrative: "Observed facts only.",
                narrativeGeneratedAt: referenceDate,
                answers: [:],
                analysisResult: nil,
                analysisGeneratedAt: nil,
                updatedAt: referenceDate
            )
            answered.answers["2026-01-05-q1"] = AnswerEntry(text: "My own synthetic answer.", updatedAt: referenceDate)
            let analyzed = DailyReport(
                day: "2026-01-06",
                narrative: "",
                narrativeGeneratedAt: nil,
                answers: [:],
                analysisResult: "Synthetic local analysis text.",
                analysisGeneratedAt: referenceDate,
                updatedAt: referenceDate
            )
            let reports = [answered, analyzed]
            let legacy = """
            [
              {
                "analysisGeneratedAt" : null,
                "analysisResult" : null,
                "answers" : {
                  "2026-01-05-q1" : {
                    "text" : "My own synthetic answer.",
                    "updatedAt" : "2026-01-05T12:00:00Z"
                  }
                },
                "day" : "2026-01-05",
                "narrative" : "Observed facts only.",
                "narrativeGeneratedAt" : "2026-01-05T12:00:00Z",
                "updatedAt" : "2026-01-05T12:00:00Z"
              }
            ]
            """
            return StoreFixture(
                store: .reports,
                legacyJSON: legacy,
                barePayloadJSON: { try self.compactPayloadJSON(reports) },
                save: { try $0.saveReports(reports) },
                loadIgnoringResult: { _ = try $0.loadReports() },
                assertLoaded: { try expectEqual(try $0.loadReports(), reports) },
                assertLegacyLoaded: { persistence in
                    try expectEqual(try persistence.loadReports(), [reports[0]], "the legacy file holds exactly its one synthetic report")
                },
                assertHealthLoaded: { persistence in
                    guard case .loaded(let value) = persistence.loadReportsHealth() else {
                        throw TestFailure("reports: expected a loaded store")
                    }
                    try expectEqual(value, reports)
                },
                assertLegacyHealthLoaded: { persistence in
                    guard case .loaded(let value) = persistence.loadReportsHealth() else {
                        throw TestFailure("reports: expected a loaded legacy store")
                    }
                    try expectEqual(value, [reports[0]], "the legacy file holds exactly its one synthetic report")
                }
            )
        case .settings:
            var settings = AppSettings()
            settings.exclusions = ["alpha", "beta"]
            settings.enabledSources = [.codex, .claudeCode]
            settings.aiEnabled = true
            settings.analysisAgent = .codex
            settings.setModel("fixture-model", for: .codex)
            settings.providerEndpoint = "https://provider.example.invalid"
            settings.providerModel = "legacy-model"
            settings.pricePerMillionInput = 1.5
            settings.pricePerMillionOutput = 6.0
            settings.usageMode = .requested
            settings.gitRepositoryPath = "/tmp/fixture-repo"
            settings.maxPreviewCharacters = 200
            let legacy = """
            {
              "aiEnabled" : true,
              "analysisAgent" : "codex",
              "enabledSources" : [
                "codex",
                "claude_code"
              ],
              "exclusions" : [
                "alpha",
                "beta"
              ],
              "gitRepositoryPath" : "/tmp/fixture-repo",
              "maxPreviewCharacters" : 200,
              "modelSelections" : [
                "codex",
                "fixture-model"
              ],
              "pricePerMillionInput" : 1.5,
              "pricePerMillionOutput" : 6,
              "providerEndpoint" : "https://provider.example.invalid",
              "providerModel" : "legacy-model",
              "usageMode" : "requested"
            }
            """
            return StoreFixture(
                store: .settings,
                legacyJSON: legacy,
                barePayloadJSON: { try self.compactPayloadJSON(settings) },
                save: { try $0.saveSettings(settings) },
                loadIgnoringResult: { _ = try $0.loadSettings() },
                assertLoaded: { try expectEqual(try $0.loadSettings(), settings) },
                assertLegacyLoaded: { try expectEqual(try $0.loadSettings(), settings) },
                assertHealthLoaded: { persistence in
                    guard case .loaded(let value) = persistence.loadSettingsHealth() else {
                        throw TestFailure("settings: expected a loaded store")
                    }
                    try expectEqual(value, settings)
                },
                assertLegacyHealthLoaded: { persistence in
                    guard case .loaded(let value) = persistence.loadSettingsHealth() else {
                        throw TestFailure("settings: expected a loaded legacy store")
                    }
                    try expectEqual(value, settings)
                }
            )
        case .manifests:
            let manifests: [SourceKind: SourceManifest] = [
                .codex: SourceManifest(lastImport: referenceDate, importedEventCount: 7, filesScanned: 3, note: nil),
                .claudeCode: SourceManifest(lastImport: nil, importedEventCount: 0, filesScanned: 0, note: "Source not detected."),
                .gitLocal: SourceManifest(lastImport: referenceDate, importedEventCount: 2, filesScanned: 1, note: "Fixture note.")
            ]
            let legacy = """
            [
              "codex",
              {
                "filesScanned" : 3,
                "importedEventCount" : 7,
                "lastImport" : "2026-01-05T12:00:00Z",
                "note" : null
              },
              "claude_code",
              {
                "filesScanned" : 0,
                "importedEventCount" : 0,
                "lastImport" : null,
                "note" : "Source not detected."
              },
              "git_local",
              {
                "filesScanned" : 1,
                "importedEventCount" : 2,
                "lastImport" : "2026-01-05T12:00:00Z",
                "note" : "Fixture note."
              }
            ]
            """
            return StoreFixture(
                store: .manifests,
                legacyJSON: legacy,
                barePayloadJSON: { try self.compactPayloadJSON(manifests) },
                save: { try $0.saveManifests(manifests) },
                loadIgnoringResult: { _ = try $0.loadManifests() },
                assertLoaded: { try expectEqual(try $0.loadManifests(), manifests) },
                assertLegacyLoaded: { try expectEqual(try $0.loadManifests(), manifests) },
                assertHealthLoaded: { persistence in
                    guard case .loaded(let value) = persistence.loadManifestsHealth() else {
                        throw TestFailure("manifests: expected a loaded store")
                    }
                    try expectEqual(value, manifests)
                },
                assertLegacyHealthLoaded: { persistence in
                    guard case .loaded(let value) = persistence.loadManifestsHealth() else {
                        throw TestFailure("manifests: expected a loaded legacy store")
                    }
                    try expectEqual(value, manifests)
                }
            )
        case .sessions:
            let sessions = [Fixtures.syntheticSession()]
            return StoreFixture(
                store: .sessions,
                legacyJSON: Fixtures.syntheticSessionsLegacyJSON,
                barePayloadJSON: { try self.compactPayloadJSON(sessions) },
                save: { try $0.saveSessions(sessions) },
                loadIgnoringResult: { _ = try $0.loadSessions() },
                assertLoaded: { try expectEqual(try $0.loadSessions(), sessions) },
                assertLegacyLoaded: { try expectEqual(try $0.loadSessions(), sessions) },
                assertHealthLoaded: { persistence in
                    guard case .loaded(let value) = persistence.loadSessionsHealth() else {
                        throw TestFailure("sessions: expected a loaded store")
                    }
                    try expectEqual(value, sessions)
                },
                assertLegacyHealthLoaded: { persistence in
                    guard case .loaded(let value) = persistence.loadSessionsHealth() else {
                        throw TestFailure("sessions: expected a loaded legacy store")
                    }
                    try expectEqual(value, sessions)
                }
            )
        case .conversations:
            let conversations = [Fixtures.syntheticStoredConversation()]
            return StoreFixture(
                store: .conversations,
                legacyJSON: Fixtures.syntheticConversationsLegacyJSON,
                barePayloadJSON: { try self.compactPayloadJSON(conversations) },
                save: { try $0.saveConversations(conversations) },
                loadIgnoringResult: { _ = try $0.loadConversations() },
                assertLoaded: { try expectEqual(try $0.loadConversations(), conversations) },
                assertLegacyLoaded: { try expectEqual(try $0.loadConversations(), conversations) },
                assertHealthLoaded: { persistence in
                    guard case .loaded(let value) = persistence.loadConversationsHealth() else {
                        throw TestFailure("conversations: expected a loaded store")
                    }
                    try expectEqual(value, conversations)
                },
                assertLegacyHealthLoaded: { persistence in
                    guard case .loaded(let value) = persistence.loadConversationsHealth() else {
                        throw TestFailure("conversations: expected a loaded legacy store")
                    }
                    try expectEqual(value, conversations)
                }
            )
        }
    }

    private func compactPayloadJSON<T: Codable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    // MARK: Envelope JSON builders

    private func envelopeJSON(store identity: String, schemaVersion: String, payloadJSON: String) -> String {
        """
        {
          "payload" : \(payloadJSON),
          "schemaVersion" : \(schemaVersion),
          "store" : "\(identity)"
        }
        """
    }

    private func envelopeJSONWithoutVersion(store identity: String, payloadJSON: String) -> String {
        """
        {
          "payload" : \(payloadJSON),
          "store" : "\(identity)"
        }
        """
    }

    private func wrongIdentity(for store: StoreName) -> String {
        let all = StoreName.allCases
        guard let index = all.firstIndex(of: store) else { return all[0].rawValue }
        return all[(index + 1) % all.count].rawValue
    }

    // MARK: Small assertion helpers

    private func fileURL(_ directory: URL, _ store: StoreName) -> URL {
        directory.appendingPathComponent(store.fileName)
    }

    private func envelopeObject(in data: Data, store: StoreName) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let envelope = object as? [String: Any] else {
            throw TestFailure("\(store.rawValue): expected a JSON envelope object at the top level")
        }
        return envelope
    }

    private func assertEnvelopeIdentity(_ data: Data, store: StoreName, version expectedVersion: Int) throws {
        let envelope = try envelopeObject(in: data, store: store)
        let identity = try require(envelope["store"] as? String, "\(store.rawValue): envelope must carry a store identity")
        try expectEqual(identity, store.rawValue, "\(store.rawValue): envelope identity must match the store")
        let version = try require(envelope["schemaVersion"] as? Int, "\(store.rawValue): envelope must carry an integer schemaVersion")
        try expectEqual(version, expectedVersion, "\(store.rawValue): envelope version must be the current supported version")
        try expectTrue(envelope["payload"] != nil, "\(store.rawValue): envelope must carry a payload")
    }

    private func assertHealthFailed(
        _ fixture: StoreFixture,
        _ persistence: PersistenceController,
        messagePart: String,
        context: String,
        privatePath: String
    ) throws {
        let store = fixture.store
        func failureOutcome() -> StoreFailure? {
            switch store {
            case .events:
                if case .failed(let failure) = persistence.loadEventsHealth() { return failure }
            case .corrections:
                if case .failed(let failure) = persistence.loadCorrectionsHealth() { return failure }
            case .reports:
                if case .failed(let failure) = persistence.loadReportsHealth() { return failure }
            case .settings:
                if case .failed(let failure) = persistence.loadSettingsHealth() { return failure }
            case .manifests:
                if case .failed(let failure) = persistence.loadManifestsHealth() { return failure }
            case .sessions:
                if case .failed(let failure) = persistence.loadSessionsHealth() { return failure }
            case .conversations:
                if case .failed(let failure) = persistence.loadConversationsHealth() { return failure }
            }
            return nil
        }

        let failure = try require(failureOutcome(), "\(context): expected a typed .failed load, not a silent default")
        try expectEqual(failure.store, store)
        try expectFalse(failure.userMessage.contains(privatePath), "\(context): the failure message must not include private paths")
        try expectTrue(failure.userMessage.contains(messagePart), "\(context): expected rejection wording about \(messagePart), got: \(failure.userMessage)")
    }

    private func assertOrdinaryLoadThrows(_ fixture: StoreFixture, _ persistence: PersistenceController, _ context: String) throws {
        do {
            try fixture.loadIgnoringResult(persistence)
            throw TestFailure("\(context): an ordinary load must not hand back rejected file content as data")
        } catch let failure as TestFailure {
            throw failure
        } catch {
            // Expected: the load threw instead of returning content.
        }
    }

    private func assertOrdinarySaveRejected(_ fixture: StoreFixture, _ persistence: PersistenceController, _ context: String) throws {
        do {
            try fixture.save(persistence)
            throw TestFailure("\(context): an ordinary direct save must be rejected")
        } catch let failure as TestFailure {
            throw failure
        } catch {
            // Expected: the save threw instead of replacing the file.
        }
    }

    // MARK: Tests

    /// Every store saves a version-1 envelope with stable identity and its
    /// full payload round-trips, on both the ordinary and typed-health paths.
    func versionOneEnvelopeRoundTripsEveryStore() throws {
        for store in StoreName.allCases {
            let fixture = makeFixture(store)
            let directory = Fixtures.makeTempDirectory("storever-envelope-\(store.rawValue)")
            let persistence = PersistenceController(directory: directory)

            try fixture.save(persistence)

            let data = try Data(contentsOf: fileURL(directory, store))
            try assertEnvelopeIdentity(data, store: store, version: store.schemaVersion)
            try fixture.assertLoaded(persistence)
            try fixture.assertHealthLoaded(persistence)
        }
    }

    /// Envelope bytes are deterministic: equal payloads saved again — in the
    /// same directory or a fresh one — produce byte-identical pretty, sorted
    /// JSON.
    func envelopeBytesAreDeterministicSortedAndPretty() throws {
        for store in StoreName.allCases {
            let fixture = makeFixture(store)
            let directory = Fixtures.makeTempDirectory("storever-determinism-\(store.rawValue)")
            let persistence = PersistenceController(directory: directory)
            try fixture.save(persistence)

            let url = fileURL(directory, store)
            let firstBytes = try Data(contentsOf: url)

            try fixture.save(persistence)
            try expectEqual(try Data(contentsOf: url), firstBytes, "\(store.rawValue): resaving the same payload must be byte-identical")

            let secondDirectory = Fixtures.makeTempDirectory("storever-determinism-\(store.rawValue)-again")
            try fixture.save(PersistenceController(directory: secondDirectory))
            try expectEqual(try Data(contentsOf: fileURL(secondDirectory, store)), firstBytes, "\(store.rawValue): the same payload must encode identically in any directory")

            let raw = String(decoding: firstBytes, as: UTF8.self)
            try expectTrue(raw.hasPrefix("{\n"), "\(store.rawValue): the envelope is pretty-printed")
            let payloadRange = try require(raw.range(of: "\"payload\""), "\(store.rawValue): envelope must carry a payload key")
            let versionRange = try require(raw.range(of: "\"schemaVersion\""), "\(store.rawValue): envelope must carry a schemaVersion key")
            let storeRange = try require(raw.range(of: "\"store\""), "\(store.rawValue): envelope must carry a store key")
            try expectTrue(
                payloadRange.lowerBound < versionRange.lowerBound && versionRange.lowerBound < storeRange.lowerBound,
                "\(store.rawValue): top-level envelope keys must be sorted"
            )
        }
    }

    /// Legacy bare payloads (schema version 0) read exactly on the ordinary
    /// and typed-health paths, and reading never rewrites the file.
    func legacyBarePayloadsReadExactlyWithoutWriteOnRead() throws {
        for store in StoreName.allCases {
            let fixture = makeFixture(store)
            let directory = Fixtures.makeTempDirectory("storever-legacy-\(store.rawValue)")
            let url = fileURL(directory, store)
            let legacyBytes = Data(fixture.legacyJSON.utf8)
            try legacyBytes.write(to: url)

            let persistence = PersistenceController(directory: directory)
            try fixture.assertLegacyLoaded(persistence)
            try fixture.assertLegacyHealthLoaded(persistence)

            try expectEqual(try Data(contentsOf: url), legacyBytes, "\(store.rawValue): reading a legacy store must not rewrite a single byte")
        }
    }

    /// The next ordinary save must not replace a legacy bare file: until the
    /// explicit migration path exists, replacing it would destroy the only
    /// original before any protected backup. Every store loads its legacy
    /// fixture exactly, rejects the ordinary save with the typed
    /// `legacyNeedsMigration` failure and its safe message, and keeps the file
    /// byte-for-byte intact.
    func ordinarySaveRejectsLegacyFilesUntilMigration() throws {
        for store in StoreName.allCases {
            let fixture = makeFixture(store)
            let directory = Fixtures.makeTempDirectory("storever-legacy-blocked-\(store.rawValue)")
            let url = fileURL(directory, store)
            let legacyBytes = Data(fixture.legacyJSON.utf8)
            try legacyBytes.write(to: url)

            let persistence = PersistenceController(directory: directory)

            // The legacy store still reads exactly, on both load paths.
            try fixture.assertLegacyLoaded(persistence)
            try fixture.assertLegacyHealthLoaded(persistence)

            // The ordinary save is typed as migration-needed, never replaced.
            do {
                try fixture.save(persistence)
                throw TestFailure("\(store.rawValue): an ordinary save over a legacy store must be rejected until migration exists")
            } catch let rejection as StoreFileRejection {
                try expectEqual(rejection, StoreFileRejection.legacyNeedsMigration, "\(store.rawValue): the rejection must be typed as migration-needed")
                let message = rejection.userMessage(for: store)
                try expectTrue(message.contains("older storage format"), "\(store.rawValue): the safe message must describe the older format, got: \(message)")
                try expectFalse(message.contains(directory.path), "\(store.rawValue): the safe message must not include private paths")
            }

            try expectEqual(try Data(contentsOf: url), legacyBytes, "\(store.rawValue): a rejected save must leave the legacy file byte-for-byte intact")
        }
    }

    /// A newer unsupported schema version (99) is a typed failure on read and
    /// an ordinary direct save must reject it, leaving the bytes untouched.
    func futureVersionEnvelopeIsRejectedAndBlocksOrdinarySave() throws {
        for store in StoreName.allCases {
            let fixture = makeFixture(store)
            let directory = Fixtures.makeTempDirectory("storever-future-\(store.rawValue)")
            let url = fileURL(directory, store)
            let futureBytes = Data(
                envelopeJSON(store: store.rawValue, schemaVersion: "99", payloadJSON: try fixture.barePayloadJSON()).utf8
            )
            try futureBytes.write(to: url)

            let persistence = PersistenceController(directory: directory)
            try assertHealthFailed(fixture, persistence, messagePart: "newer version of Reflect", context: "\(store.rawValue) future version", privatePath: directory.path)
            try assertOrdinaryLoadThrows(fixture, persistence, "\(store.rawValue) future version")
            try assertOrdinarySaveRejected(fixture, persistence, "\(store.rawValue) future version")

            try expectEqual(try Data(contentsOf: url), futureBytes, "\(store.rawValue): a rejected save must leave the file byte-for-byte intact")
        }
    }

    /// A wrong-store envelope is a typed failure on read, and an ordinary
    /// direct save must reject it, leaving the bytes untouched.
    func wrongStoreEnvelopeIsRejectedAndBlocksOrdinarySave() throws {
        for store in StoreName.allCases {
            let fixture = makeFixture(store)
            let directory = Fixtures.makeTempDirectory("storever-wrongstore-\(store.rawValue)")
            let url = fileURL(directory, store)
            let wrongBytes = Data(
                envelopeJSON(store: wrongIdentity(for: store), schemaVersion: "1", payloadJSON: try fixture.barePayloadJSON()).utf8
            )
            try wrongBytes.write(to: url)

            let persistence = PersistenceController(directory: directory)
            try assertHealthFailed(fixture, persistence, messagePart: "different store", context: "\(store.rawValue) wrong-store", privatePath: directory.path)
            try assertOrdinaryLoadThrows(fixture, persistence, "\(store.rawValue) wrong-store")
            try assertOrdinarySaveRejected(fixture, persistence, "\(store.rawValue) wrong-store")

            try expectEqual(try Data(contentsOf: url), wrongBytes, "\(store.rawValue): a rejected save must leave the file byte-for-byte intact")
        }
    }

    /// Malformed payloads and envelopes, missing versions, invalid versions,
    /// and explicit version 0 are all typed failures on read, and ordinary
    /// direct saves reject each one without changing a single byte.
    func malformedEnvelopesAndVersionsAreRejectedAndBlockOrdinarySave() throws {
        for store in StoreName.allCases {
            let fixture = makeFixture(store)
            let payloadJSON = try fixture.barePayloadJSON()
            let variants: [(name: String, json: String, messagePart: String)] = [
                ("truncated-envelope", "{\"store\": \"\(store.rawValue)\",", "could not be read or decoded"),
                ("envelope-missing-version", envelopeJSONWithoutVersion(store: store.rawValue, payloadJSON: payloadJSON), "could not be read or decoded"),
                ("non-integer-version", envelopeJSON(store: store.rawValue, schemaVersion: "\"one\"", payloadJSON: payloadJSON), "unreadable schema version"),
                ("zero-version", envelopeJSON(store: store.rawValue, schemaVersion: "0", payloadJSON: payloadJSON), "unreadable schema version"),
                ("payload-of-wrong-shape", envelopeJSON(store: store.rawValue, schemaVersion: "1", payloadJSON: "\"synthetic\""), "could not be read or decoded"),
                ("corrupt-bare-json", "{\"synthetic-damaged-fixture\":", "could not be read or decoded")
            ]

            for variant in variants {
                let directory = Fixtures.makeTempDirectory("storever-malformed-\(store.rawValue)-\(variant.name)")
                let url = fileURL(directory, store)
                let variantBytes = Data(variant.json.utf8)
                try variantBytes.write(to: url)

                let persistence = PersistenceController(directory: directory)
                let context = "\(store.rawValue) \(variant.name)"
                try assertHealthFailed(fixture, persistence, messagePart: variant.messagePart, context: context, privatePath: directory.path)
                try assertOrdinaryLoadThrows(fixture, persistence, context)
                try assertOrdinarySaveRejected(fixture, persistence, context)

                try expectEqual(try Data(contentsOf: url), variantBytes, "\(context): a rejected save must leave the file byte-for-byte intact")
            }
        }
    }

    /// Explicit recovery preserves the damaged bytes in a verified backup and
    /// installs a fresh, valid version-1 envelope holding the store default.
    func recoveryPreservesDamagedBytesAndInstallsVersionOneEnvelope() throws {
        for store in StoreName.allCases {
            let directory = Fixtures.makeTempDirectory("storever-recover-\(store.rawValue)")
            let url = fileURL(directory, store)
            let original = Data("synthetic damaged bytes for \(store.rawValue) fixture".utf8)
            try original.write(to: url)

            let persistence = PersistenceController(directory: directory)
            let outcome = persistence.recoverStore(store)
            guard case .recovered = outcome else {
                throw TestFailure("\(store.rawValue): expected recovery to succeed, got \(outcome)")
            }

            let backups = directory.appendingPathComponent(PersistenceController.damagedBackupsFolderName, isDirectory: true)
            let backupFiles = try FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
            try expectEqual(backupFiles.count, 1, "\(store.rawValue): exactly one backup is created")
            try expectEqual(try Data(contentsOf: backupFiles[0]), original, "\(store.rawValue): the backup must preserve the damaged bytes exactly")

            let replacement = try Data(contentsOf: url)
            try assertEnvelopeIdentity(replacement, store: store, version: store.schemaVersion)

            switch store {
            case .events:
                guard case .loaded(let value) = persistence.loadEventsHealth() else {
                    throw TestFailure("events: expected a loaded store after recovery")
                }
                try expectTrue(value.isEmpty, "events: the recovered store starts as a valid default")
            case .corrections:
                guard case .loaded(let value) = persistence.loadCorrectionsHealth() else {
                    throw TestFailure("corrections: expected a loaded store after recovery")
                }
                try expectTrue(value.isEmpty, "corrections: the recovered store starts as a valid default")
            case .reports:
                guard case .loaded(let value) = persistence.loadReportsHealth() else {
                    throw TestFailure("reports: expected a loaded store after recovery")
                }
                try expectTrue(value.isEmpty, "reports: the recovered store starts as a valid default")
            case .settings:
                guard case .loaded(let value) = persistence.loadSettingsHealth() else {
                    throw TestFailure("settings: expected a loaded store after recovery")
                }
                try expectEqual(value, AppSettings.default(), "settings: the recovered store starts as a valid default")
            case .manifests:
                guard case .loaded(let value) = persistence.loadManifestsHealth() else {
                    throw TestFailure("manifests: expected a loaded store after recovery")
                }
                try expectTrue(value.isEmpty, "manifests: the recovered store starts as a valid default")
            case .sessions:
                guard case .loaded(let value) = persistence.loadSessionsHealth() else {
                    throw TestFailure("sessions: expected a loaded store after recovery")
                }
                try expectTrue(value.isEmpty, "sessions: the recovered store starts as a valid default")
            case .conversations:
                guard case .loaded(let value) = persistence.loadConversationsHealth() else {
                    throw TestFailure("conversations: expected a loaded store after recovery")
                }
                try expectTrue(value.isEmpty, "conversations: the recovered store starts as a valid default")
            }
        }
    }

    static var entries: [TestEntry] {
        let tests = StoreVersioningTests()
        return [
            TestEntry(suite: suiteName, name: "versionOneEnvelopeRoundTripsEveryStore") {
                try tests.versionOneEnvelopeRoundTripsEveryStore()
            },
            TestEntry(suite: suiteName, name: "envelopeBytesAreDeterministicSortedAndPretty") {
                try tests.envelopeBytesAreDeterministicSortedAndPretty()
            },
            TestEntry(suite: suiteName, name: "legacyBarePayloadsReadExactlyWithoutWriteOnRead") {
                try tests.legacyBarePayloadsReadExactlyWithoutWriteOnRead()
            },
            TestEntry(suite: suiteName, name: "ordinarySaveRejectsLegacyFilesUntilMigration") {
                try tests.ordinarySaveRejectsLegacyFilesUntilMigration()
            },
            TestEntry(suite: suiteName, name: "futureVersionEnvelopeIsRejectedAndBlocksOrdinarySave") {
                try tests.futureVersionEnvelopeIsRejectedAndBlocksOrdinarySave()
            },
            TestEntry(suite: suiteName, name: "wrongStoreEnvelopeIsRejectedAndBlocksOrdinarySave") {
                try tests.wrongStoreEnvelopeIsRejectedAndBlocksOrdinarySave()
            },
            TestEntry(suite: suiteName, name: "malformedEnvelopesAndVersionsAreRejectedAndBlockOrdinarySave") {
                try tests.malformedEnvelopesAndVersionsAreRejectedAndBlockOrdinarySave()
            },
            TestEntry(suite: suiteName, name: "recoveryPreservesDamagedBytesAndInstallsVersionOneEnvelope") {
                try tests.recoveryPreservesDamagedBytesAndInstallsVersionOneEnvelope()
            }
        ]
    }
}
