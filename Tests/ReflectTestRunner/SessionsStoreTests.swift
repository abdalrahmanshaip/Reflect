import Foundation
@testable import ReflectLib

/// M2 slice 1 coverage for the new versioned `sessions` store: schema-version
/// 1 envelope round-trip, fail-closed behavior, and the additive extension of
/// the explicit migration — absent on legacy installations is a no-op, a
/// legacy bare sessions payload participates in preflight, verified backups,
/// journaling, retry, rollback, and recovery like any other store. Every
/// fixture is synthetic and lives in a fresh temporary directory; no real
/// user store is ever opened.
struct SessionsStoreTests {
    static let suiteName = "SessionsStoreTests"

    // MARK: Failure-injection seam (tests only)

    /// Wraps the real FileManager-backed migration file service and fails
    /// calls chosen by the test.
    private final class MigrationFailureInjector: MigrationFileServing {
        private let base = SystemMigrationFileService()
        var shouldFailReplace: (URL) -> Bool = { _ in false }

        func data(at url: URL) throws -> Data { try base.data(at: url) }
        func exists(_ url: URL) -> Bool { base.exists(url) }
        func writeAtomic(_ data: Data, to url: URL) throws { try base.writeAtomic(data, to: url) }
        func replaceItem(at target: URL, withItemAt staged: URL) throws {
            if shouldFailReplace(target) { throw TestFailure("injected replacement failure") }
            try base.replaceItem(at: target, withItemAt: staged)
        }
        func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
            try base.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
        }
        func contentsOfDirectory(at url: URL) throws -> [URL] {
            try base.contentsOfDirectory(at: url)
        }
    }

    // MARK: Helpers

    private let referenceDate = Date(timeIntervalSince1970: 1_767_614_400)

    /// Legacy bare events payload (schema version 0), synthetic.
    private let legacyEventsJSON = """
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

    private func storeURL(_ directory: URL, _ store: StoreName) -> URL {
        directory.appendingPathComponent(store.fileName)
    }

    private func migrationFolders(in directory: URL) throws -> [URL] {
        let root = directory.appendingPathComponent(PersistenceController.migrationBackupsFolderName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func assertEnvelope(_ data: Data, store: StoreName, context: String) throws {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let envelope = object as? [String: Any] else {
            throw TestFailure("\(context): expected a JSON envelope object")
        }
        try expectEqual(envelope["store"] as? String, store.rawValue, "\(context): envelope identity")
        try expectEqual(envelope["schemaVersion"] as? Int, store.schemaVersion, "\(context): envelope version")
        try expectTrue(envelope["payload"] != nil, "\(context): envelope payload present")
    }

    // MARK: Store behavior

    func sessionsStoreRoundTripsVersionOneEnvelope() throws {
        let directory = Fixtures.makeTempDirectory("sessions-roundtrip")
        let persistence = PersistenceController(directory: directory)

        guard case .missing = persistence.loadSessionsHealth() else {
            throw TestFailure("an absent sessions store must report .missing")
        }

        let sessions = [Fixtures.syntheticSession()]
        try persistence.saveSessions(sessions)

        let data = try Data(contentsOf: storeURL(directory, .sessions))
        try assertEnvelope(data, store: .sessions, context: "sessions envelope")
        try expectEqual(try persistence.loadSessions(), sessions)
        guard case .loaded(let healthValue) = persistence.loadSessionsHealth() else {
            throw TestFailure("expected a loaded sessions store")
        }
        try expectEqual(healthValue, sessions)
    }

    func evidenceEventBehaviorIsUnchangedByTheSessionsStore() throws {
        // The sessions store adds a separate ID space; EvidenceEvent identity
        // and deduplication contracts stay exactly as accepted in M1.
        let first = EvidenceIdentity.stableID(source: .codex, path: "/tmp/fixture/a.jsonl", line: 3, recordType: "message.user")
        let second = EvidenceIdentity.stableID(source: .codex, path: "/tmp/fixture/a.jsonl", line: 3, recordType: "message.user")
        try expectEqual(first, second, "EvidenceEvent stable IDs remain deterministic")

        let existing = Fixtures.dayEvents(count: 2)
        let incoming = [existing[1], Fixtures.dayEvents(count: 3)[2]]
        let (merged, added) = EventDeduplicator.merge(existing: existing, incoming: incoming)
        try expectEqual(added, 1, "EventDeduplicator keeps its idempotent merge behavior")
        try expectEqual(merged.count, 3)

        try expectEqual(StoreName.events.schemaVersion, 1, "events stays at schema version 1")
        try expectEqual(StoreName.events.fileName, "events.json")
        try expectNotEqual(SessionIdentity.sessionID(source: .codex, sourceSessionID: "s", filePath: "/tmp/x"), EvidenceIdentity.stableID(source: .codex, path: "/tmp/x", line: 1, recordType: "message.user"), "session IDs form a separate identity space")
    }

    // MARK: Additive migration

    func migrationWithoutSessionsStoreLeavesItAbsent() throws {
        let directory = Fixtures.makeTempDirectory("sessions-migr-absent")
        try Data(legacyEventsJSON.utf8).write(to: storeURL(directory, .events))
        let persistence = PersistenceController(directory: directory)

        let outcome = persistence.migrateLegacyStores()
        guard case .migrated(_, let stores) = outcome else {
            throw TestFailure("expected the events store to migrate, got \(outcome)")
        }
        try expectEqual(stores, [StoreName.events], "an absent sessions store must not participate")
        try expectFalse(FileManager.default.fileExists(atPath: storeURL(directory, .sessions).path), "migration must not create a sessions store that was never there")
        guard case .missing = persistence.loadSessionsHealth() else {
            throw TestFailure("the sessions store must remain absent after migration")
        }
    }

    func migrationIncludesLegacySessionsStoreWithBackupAndRoundTrip() throws {
        let directory = Fixtures.makeTempDirectory("sessions-migr-present")
        let legacySessions = Data(Fixtures.syntheticSessionsLegacyJSON.utf8)
        try legacySessions.write(to: storeURL(directory, .sessions))
        try Data(legacyEventsJSON.utf8).write(to: storeURL(directory, .events))
        let persistence = PersistenceController(directory: directory)

        let outcome = persistence.migrateLegacyStores()
        guard case .migrated(let id, let stores) = outcome else {
            throw TestFailure("expected a migrated outcome, got \(outcome)")
        }
        try expectEqual(stores, [StoreName.events, StoreName.sessions], "every present legacy store participates, including sessions")

        let folders = try migrationFolders(in: directory)
        try expectEqual(folders.count, 1)
        try expectEqual(folders[0].lastPathComponent, id.uuidString)
        try expectEqual(try Data(contentsOf: folders[0].appendingPathComponent("sessions.json")), legacySessions, "the verified backup preserves the legacy sessions bytes exactly")

        try assertEnvelope(try Data(contentsOf: storeURL(directory, .sessions)), store: .sessions, context: "migrated sessions")
        try expectEqual(try persistence.loadSessions(), [Fixtures.syntheticSession()], "the migrated sessions payload round-trips exactly")
    }

    func migrationPreflightAbortsOnDamagedSessionsStore() throws {
        for (name, bytes, messagePart) in [
            ("corrupt", Data("{\"synthetic-damaged-sessions\":".utf8), "could not be read or decoded"),
            ("newer", Data("{\"payload\" : [], \"schemaVersion\" : 99, \"store\" : \"sessions\"}".utf8), "newer version of Reflect"),
            ("wrongstore", Data("{\"payload\" : [], \"schemaVersion\" : 1, \"store\" : \"events\"}".utf8), "different store")
        ] as [(String, Data, String)] {
            let directory = Fixtures.makeTempDirectory("sessions-migr-\(name)")
            try Data(legacyEventsJSON.utf8).write(to: storeURL(directory, .events))
            try bytes.write(to: storeURL(directory, .sessions))
            let persistence = PersistenceController(directory: directory)

            let outcome = persistence.migrateLegacyStores()
            guard case .failed(let message) = outcome else {
                throw TestFailure("\(name): expected a failed preflight, got \(outcome)")
            }
            try expectTrue(message.contains(messagePart), "\(name): expected rejection wording, got: \(message)")
            try expectFalse(message.contains(directory.path), "\(name): the message must not include private paths")
            try expectEqual(try Data(contentsOf: storeURL(directory, .events)), Data(legacyEventsJSON.utf8), "\(name): preflight must not change a byte")
            try expectEqual(try Data(contentsOf: storeURL(directory, .sessions)), bytes, "\(name): preflight must not change a byte")
            try expectTrue(try migrationFolders(in: directory).isEmpty, "\(name): no migration folder may be created on a preflight abort")
        }
    }

    func interruptedMigrationRetriesAndCompletesTheSessionsStore() throws {
        let directory = Fixtures.makeTempDirectory("sessions-migr-retry")
        let legacySessions = Data(Fixtures.syntheticSessionsLegacyJSON.utf8)
        try legacySessions.write(to: storeURL(directory, .sessions))
        try Data(legacyEventsJSON.utf8).write(to: storeURL(directory, .events))

        let injector = MigrationFailureInjector()
        injector.shouldFailReplace = { $0.lastPathComponent == StoreName.sessions.fileName }
        let persistence = PersistenceController(directory: directory, migrationFiles: injector)

        let failed = persistence.migrateLegacyStores()
        guard case .failed = failed else {
            throw TestFailure("expected the interruption, got \(failed)")
        }
        try assertEnvelope(try Data(contentsOf: storeURL(directory, .events)), store: .events, context: "events after interruption")
        try expectEqual(try Data(contentsOf: storeURL(directory, .sessions)), legacySessions, "sessions must still be the legacy original after the interruption")

        injector.shouldFailReplace = { _ in false }
        guard case .migrated = persistence.migrateLegacyStores() else {
            throw TestFailure("expected the retry to complete")
        }
        try assertEnvelope(try Data(contentsOf: storeURL(directory, .sessions)), store: .sessions, context: "migrated sessions after retry")
        try expectEqual(try persistence.loadSessions(), [Fixtures.syntheticSession()])
    }

    func rollbackRestoresLegacySessionsBytes() throws {
        let directory = Fixtures.makeTempDirectory("sessions-migr-rollback")
        let legacySessions = Data(Fixtures.syntheticSessionsLegacyJSON.utf8)
        try legacySessions.write(to: storeURL(directory, .sessions))
        try Data(legacyEventsJSON.utf8).write(to: storeURL(directory, .events))
        let persistence = PersistenceController(directory: directory)

        guard case .migrated = persistence.migrateLegacyStores() else {
            throw TestFailure("expected the migration to complete")
        }
        let outcome = persistence.rollbackLegacyStoreMigration()
        guard case .rolledBack(_, let stores) = outcome else {
            throw TestFailure("expected a rolled-back outcome, got \(outcome)")
        }
        try expectTrue(stores.contains(.sessions), "sessions participates in the rollback")
        try expectEqual(try Data(contentsOf: storeURL(directory, .sessions)), legacySessions, "rollback must restore the exact legacy sessions bytes")
        try expectEqual(try persistence.loadSessions(), [Fixtures.syntheticSession()], "the restored legacy store reads exactly")

        do {
            try persistence.saveSessions([])
            throw TestFailure("an ordinary save over a restored legacy sessions store must stay rejected")
        } catch let rejection as StoreFileRejection {
            try expectEqual(rejection, StoreFileRejection.legacyNeedsMigration)
        }
    }

    func migrationLockBlocksSessionReadsSavesAndImports() throws {
        let directory = Fixtures.makeTempDirectory("sessions-migr-lock")
        let legacySessions = Data(Fixtures.syntheticSessionsLegacyJSON.utf8)
        try legacySessions.write(to: storeURL(directory, .sessions))
        try Data(legacyEventsJSON.utf8).write(to: storeURL(directory, .events))

        let injector = MigrationFailureInjector()
        injector.shouldFailReplace = { $0.lastPathComponent == StoreName.sessions.fileName }
        let persistence = PersistenceController(directory: directory, migrationFiles: injector)
        guard case .failed = persistence.migrateLegacyStores() else {
            throw TestFailure("expected the interruption setup to fail")
        }

        guard case .failed(let failure) = persistence.loadSessionsHealth() else {
            throw TestFailure("expected a typed failure while the migration is in progress")
        }
        try expectTrue(failure.userMessage.contains("migration is in progress"), "expected the migration message, got: \(failure.userMessage)")

        do {
            try persistence.saveSessions([])
            throw TestFailure("an ordinary sessions save must be blocked while the migration is in progress")
        } catch let rejection as StoreFileRejection {
            try expectEqual(rejection, StoreFileRejection.migrationInProgress)
        }

        let importFile = Fixtures.makeTempDirectory("sessions-migr-lock-src").appendingPathComponent("rollout-lock-fixture.jsonl")
        Fixtures.write(Fixtures.codexFixtureText, to: importFile)
        let service = SessionImportService(persistence: persistence)
        let outcome = service.importCodexSessionFile(at: importFile, now: referenceDate)
        guard case .failed(let importMessage) = outcome else {
            throw TestFailure("an import during a migration must fail, got \(outcome)")
        }
        try expectTrue(importMessage.contains("migration is in progress"), "the import must surface the migration lock, got: \(importMessage)")

        injector.shouldFailReplace = { _ in false }
        guard case .migrated = persistence.migrateLegacyStores() else {
            throw TestFailure("expected the retry to complete")
        }
    }

    func recoveryInstallsFreshSessionsEnvelopeAndPreservesDamagedBytes() throws {
        let directory = Fixtures.makeTempDirectory("sessions-recovery")
        let storeURL = storeURL(directory, .sessions)
        let damaged = Data("synthetic damaged sessions bytes".utf8)
        try damaged.write(to: storeURL)
        let persistence = PersistenceController(directory: directory)

        guard case .failed = persistence.loadSessionsHealth() else {
            throw TestFailure("the damaged sessions store must be a typed failure")
        }

        let outcome = persistence.recoverStore(.sessions)
        guard case .recovered = outcome else {
            throw TestFailure("expected recovery to succeed, got \(outcome)")
        }

        let backups = directory.appendingPathComponent(PersistenceController.damagedBackupsFolderName, isDirectory: true)
        let backupFiles = try FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
        try expectEqual(backupFiles.count, 1, "exactly one backup is created")
        try expectEqual(try Data(contentsOf: backupFiles[0]), damaged, "the backup preserves the damaged bytes exactly")

        try assertEnvelope(try Data(contentsOf: storeURL), store: .sessions, context: "recovered sessions")
        try expectEqual(try persistence.loadSessions(), [] as [WorkSession], "the recovered store starts as a valid default")
        try persistence.saveSessions([Fixtures.syntheticSession()])
        try expectEqual(try persistence.loadSessions().count, 1, "the recovered store accepts new content")
    }

    static var entries: [TestEntry] {
        let tests = SessionsStoreTests()
        return [
            TestEntry(suite: suiteName, name: "sessionsStoreRoundTripsVersionOneEnvelope") {
                try tests.sessionsStoreRoundTripsVersionOneEnvelope()
            },
            TestEntry(suite: suiteName, name: "evidenceEventBehaviorIsUnchangedByTheSessionsStore") {
                try tests.evidenceEventBehaviorIsUnchangedByTheSessionsStore()
            },
            TestEntry(suite: suiteName, name: "migrationWithoutSessionsStoreLeavesItAbsent") {
                try tests.migrationWithoutSessionsStoreLeavesItAbsent()
            },
            TestEntry(suite: suiteName, name: "migrationIncludesLegacySessionsStoreWithBackupAndRoundTrip") {
                try tests.migrationIncludesLegacySessionsStoreWithBackupAndRoundTrip()
            },
            TestEntry(suite: suiteName, name: "migrationPreflightAbortsOnDamagedSessionsStore") {
                try tests.migrationPreflightAbortsOnDamagedSessionsStore()
            },
            TestEntry(suite: suiteName, name: "interruptedMigrationRetriesAndCompletesTheSessionsStore") {
                try tests.interruptedMigrationRetriesAndCompletesTheSessionsStore()
            },
            TestEntry(suite: suiteName, name: "rollbackRestoresLegacySessionsBytes") {
                try tests.rollbackRestoresLegacySessionsBytes()
            },
            TestEntry(suite: suiteName, name: "migrationLockBlocksSessionReadsSavesAndImports") {
                try tests.migrationLockBlocksSessionReadsSavesAndImports()
            },
            TestEntry(suite: suiteName, name: "recoveryInstallsFreshSessionsEnvelopeAndPreservesDamagedBytes") {
                try tests.recoveryInstallsFreshSessionsEnvelopeAndPreservesDamagedBytes()
            }
        ]
    }
}
