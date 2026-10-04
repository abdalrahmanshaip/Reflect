import Foundation
@testable import ReflectLib

/// M1b2 coverage for the explicit legacy-store migration: durable safe
/// upgrades from bare schema-version-0 files to the current version-1
/// envelope with verified byte-for-byte backups, a phase-journaled manifest,
/// resumable interruptions, explicit rollback, and a migration lock that
/// blocks ordinary reads and saves while a mixed generation is on disk.
/// Every fixture is synthetic and lives in a fresh temporary directory; no
/// real user data is ever read and the default Application Support directory
/// is never touched.
struct PersistenceMigrationTests {
    static let suiteName = "PersistenceMigrationTests"

    private let referenceDate = Date(timeIntervalSince1970: 1_767_614_400)

    // MARK: Failure-injection seam (tests only)

    /// Wraps the real FileManager-backed migration file service and fails
    /// calls chosen by the test, avoiding root-sensitive permission games.
    final class MigrationFailureInjector: MigrationFileServing {
        struct Call {
            enum Kind { case read, write, replace, createDirectory, list }
            let kind: Kind
            let url: URL
        }

        private let base = SystemMigrationFileService()
        var shouldFail: (Call) -> Bool = { _ in false }

        func data(at url: URL) throws -> Data {
            if shouldFail(Call(kind: .read, url: url)) { throw TestFailure("injected read failure") }
            return try base.data(at: url)
        }

        func exists(_ url: URL) -> Bool {
            base.exists(url)
        }

        func writeAtomic(_ data: Data, to url: URL) throws {
            if shouldFail(Call(kind: .write, url: url)) { throw TestFailure("injected write failure") }
            try base.writeAtomic(data, to: url)
        }

        func replaceItem(at target: URL, withItemAt staged: URL) throws {
            if shouldFail(Call(kind: .replace, url: target)) { throw TestFailure("injected replacement failure") }
            try base.replaceItem(at: target, withItemAt: staged)
        }

        func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
            if shouldFail(Call(kind: .createDirectory, url: url)) { throw TestFailure("injected directory failure") }
            try base.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
        }

        func contentsOfDirectory(at url: URL) throws -> [URL] {
            if shouldFail(Call(kind: .list, url: url)) { throw TestFailure("injected listing failure") }
            return try base.contentsOfDirectory(at: url)
        }
    }

    // MARK: Synthetic legacy fixtures (schema version 0 bare payloads)

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

    private struct LegacyFixture {
        let store: StoreName
        let legacyJSON: String
        let assertLoaded: (PersistenceController) throws -> Void
    }

    /// Legacy JSON matches exactly what earlier Reflect builds wrote on this
    /// toolchain, including enum-keyed dictionaries as alternating arrays.
    private func makeFixture(_ store: StoreName) -> LegacyFixture {
        switch store {
        case .events:
            let expected = [syntheticEvent(id: "fixture-event-1")]
            let json = """
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
            return LegacyFixture(store: .events, legacyJSON: json) { persistence in
                try expectEqual(try persistence.loadEvents(), expected)
            }
        case .corrections:
            let expected = [
                AttributionCorrection(eventId: "fixture-event-1", attribution: .you, updatedAt: referenceDate),
                AttributionCorrection(eventId: "fixture-event-2", attribution: .agent, updatedAt: referenceDate)
            ]
            let json = """
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
            return LegacyFixture(store: .corrections, legacyJSON: json) { persistence in
                try expectEqual(try persistence.loadCorrections(), expected)
            }
        case .reports:
            var report = DailyReport(
                day: "2026-01-05",
                narrative: "Observed facts only.",
                narrativeGeneratedAt: referenceDate,
                answers: [:],
                analysisResult: nil,
                analysisGeneratedAt: nil,
                updatedAt: referenceDate
            )
            report.answers["2026-01-05-q1"] = AnswerEntry(text: "My own synthetic answer.", updatedAt: referenceDate)
            let expected = [report]
            let json = """
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
            return LegacyFixture(store: .reports, legacyJSON: json) { persistence in
                try expectEqual(try persistence.loadReports(), expected)
            }
        case .settings:
            var expected = AppSettings()
            expected.exclusions = ["alpha", "beta"]
            expected.enabledSources = [.codex, .claudeCode]
            expected.aiEnabled = true
            expected.analysisAgent = .codex
            expected.setModel("fixture-model", for: .codex)
            expected.providerEndpoint = "https://provider.example.invalid"
            expected.providerModel = "legacy-model"
            expected.pricePerMillionInput = 1.5
            expected.pricePerMillionOutput = 6.0
            expected.usageMode = .requested
            expected.gitRepositoryPath = "/tmp/fixture-repo"
            expected.maxPreviewCharacters = 200
            let json = """
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
            return LegacyFixture(store: .settings, legacyJSON: json) { persistence in
                try expectEqual(try persistence.loadSettings(), expected)
            }
        case .manifests:
            let expected: [SourceKind: SourceManifest] = [
                .codex: SourceManifest(lastImport: referenceDate, importedEventCount: 7, filesScanned: 3, note: nil),
                .claudeCode: SourceManifest(lastImport: nil, importedEventCount: 0, filesScanned: 0, note: "Source not detected."),
                .gitLocal: SourceManifest(lastImport: referenceDate, importedEventCount: 2, filesScanned: 1, note: "Fixture note.")
            ]
            let json = """
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
            return LegacyFixture(store: .manifests, legacyJSON: json) { persistence in
                try expectEqual(try persistence.loadManifests(), expected)
            }
        case .sessions:
            let expected = [Fixtures.syntheticSession()]
            return LegacyFixture(store: .sessions, legacyJSON: Fixtures.syntheticSessionsLegacyJSON) { persistence in
                try expectEqual(try persistence.loadSessions(), expected)
            }
        case .conversations:
            let expected = [Fixtures.syntheticStoredConversation()]
            return LegacyFixture(store: .conversations, legacyJSON: Fixtures.syntheticConversationsLegacyJSON) { persistence in
                try expectEqual(try persistence.loadConversations(), expected)
            }
        }
    }

    // MARK: Small helpers

    @discardableResult
    private func writeLegacyFiles(_ stores: [StoreName], in directory: URL) throws -> [StoreName: Data] {
        var originals: [StoreName: Data] = [:]
        for store in stores {
            let fixture = makeFixture(store)
            let bytes = Data(fixture.legacyJSON.utf8)
            try bytes.write(to: directory.appendingPathComponent(store.fileName))
            originals[store] = bytes
        }
        return originals
    }

    private func storeURL(_ directory: URL, _ store: StoreName) -> URL {
        directory.appendingPathComponent(store.fileName)
    }

    private func backupsRoot(_ directory: URL) -> URL {
        directory.appendingPathComponent(PersistenceController.migrationBackupsFolderName, isDirectory: true)
    }

    private func migrationFolders(in directory: URL) throws -> [URL] {
        let root = backupsRoot(directory)
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func readManifest(folder: URL) throws -> StoreMigrationManifest {
        let data = try Data(contentsOf: folder.appendingPathComponent(StoreMigrationManifest.fileName))
        return try JSONDecoder().decode(StoreMigrationManifest.self, from: data)
    }

    @discardableResult
    private func expectMigrationFailed(_ outcome: StoreMigrationOutcome, _ context: String) throws -> String {
        guard case .failed(let message) = outcome else {
            throw TestFailure("\(context): expected a failed outcome, got \(outcome)")
        }
        try expectFalse(message.isEmpty, "\(context): the failure must carry a safe message")
        return message
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

    /// Fails the atomic replacement of `store`'s store file, which interrupts
    /// an apply phase after the earlier participants were already replaced.
    private func failReplacementOf(_ store: StoreName) -> (MigrationFailureInjector.Call) -> Bool {
        { call in call.kind == .replace && call.url.lastPathComponent == store.fileName }
    }

    /// Fails the direct restore write of `store`'s legacy original during
    /// rollback (backup writes live inside Migration Backups and are excluded).
    private func failRollbackRestoreOf(_ store: StoreName) -> (MigrationFailureInjector.Call) -> Bool {
        { call in
            call.kind == .write
                && call.url.lastPathComponent == store.fileName
                && !call.url.pathComponents.contains(PersistenceController.migrationBackupsFolderName)
        }
    }

    // MARK: Tests

    /// All six legacy stores preflight, migrate, and round-trip exactly; each
    /// original is preserved byte-for-byte in a verified backup that is kept
    /// after completion. The `sessions` store participates like any other:
    /// on installations where it is absent, preflight simply finds nothing.
    func migrationUpgradesAllSixLegacyStoresAndRetainsVerifiedBackups() throws {
        let directory = Fixtures.makeTempDirectory("migr-all-five")
        let originals = try writeLegacyFiles(StoreName.allCases, in: directory)
        let persistence = PersistenceController(directory: directory)

        let outcome = persistence.migrateLegacyStores()
        guard case .migrated(let id, let stores) = outcome else {
            throw TestFailure("expected a migrated outcome, got \(outcome)")
        }
        try expectEqual(stores, Array(StoreName.allCases), "every legacy store participates")

        let folders = try migrationFolders(in: directory)
        try expectEqual(folders.count, 1, "exactly one migration folder is created")
        try expectEqual(folders[0].lastPathComponent, id.uuidString, "the backup folder is named by the migration ID")

        for store in StoreName.allCases {
            try makeFixture(store).assertLoaded(persistence)
            let migratedBytes = try Data(contentsOf: storeURL(directory, store))
            try assertEnvelope(migratedBytes, store: store, context: store.rawValue)
            let backupBytes = try Data(contentsOf: folders[0].appendingPathComponent(store.fileName))
            try expectEqual(backupBytes, originals[store], "\(store.rawValue): the backup preserves the original bytes exactly")
        }

        let manifest = try readManifest(folder: folders[0])
        try expectEqual(manifest.status, StoreMigrationProgress.complete, "the manifest records completion")
        try expectEqual(manifest.stores.count, 7)

        // Completion lifts the lock: ordinary saves work again.
        try persistence.saveEvents([syntheticEvent(id: "post-migration")])
        try expectEqual(try persistence.loadEvents().count, 1)
    }

    /// Missing and already-current stores are no-ops: nothing is backed up,
    /// no journal is created, and the outcome reports everything current.
    func migrationIsNoOpForCurrentAndMissingStores() throws {
        for scenario in ["all-current", "empty", "mixed"] {
            let directory = Fixtures.makeTempDirectory("migr-noop-\(scenario)")
            let persistence = PersistenceController(directory: directory)

            switch scenario {
            case "all-current":
                try persistence.saveEvents([syntheticEvent(id: "cur")])
                try persistence.saveCorrections([])
                try persistence.saveReports([])
                try persistence.saveSettings(AppSettings.default())
                try persistence.saveManifests([:])
            case "empty":
                break
            default:
                try persistence.saveReports([])
            }

            let outcome = persistence.migrateLegacyStores()
            try expectEqual(outcome, StoreMigrationOutcome.alreadyCurrent, "\(scenario): expected a no-op outcome")
            try expectTrue(try migrationFolders(in: directory).isEmpty, "\(scenario): no migration folder may be created")

            // The no-op left every store readable and saves work.
            try persistence.saveEvents([syntheticEvent(id: "post")])
        }
    }

    /// Corrupt, wrong-store, and newer-schema files abort preflight before
    /// any store is touched: every byte stays identical and no journal or
    /// backup is created.
    func preflightRejectionsAbortBeforeAnyByteChanges() throws {
        let directory = Fixtures.makeTempDirectory("migr-preflight")
        let originals = try writeLegacyFiles([.events], in: directory)
        let corrupt = Data("{\"synthetic-damaged-fixture\":".utf8)
        try corrupt.write(to: storeURL(directory, .reports))
        let newer = Data("""
        {"payload" : [], "schemaVersion" : 99, "store" : "settings"}
        """.utf8)
        try newer.write(to: storeURL(directory, .settings))
        let wrongStore = Data("""
        {"payload" : [], "schemaVersion" : 1, "store" : "manifests"}
        """.utf8)
        try wrongStore.write(to: storeURL(directory, .corrections))
        let allOriginals: [URL: Data] = [
            storeURL(directory, .events): originals[.events]!,
            storeURL(directory, .reports): corrupt,
            storeURL(directory, .settings): newer,
            storeURL(directory, .corrections): wrongStore
        ]

        let persistence = PersistenceController(directory: directory)
        let outcome = persistence.migrateLegacyStores()
        let message = try expectMigrationFailed(outcome, "preflight with damaged stores")

        for (url, bytes) in allOriginals {
            try expectEqual(try Data(contentsOf: url), bytes, "\(url.lastPathComponent): preflight must not change a byte")
        }
        try expectTrue(try migrationFolders(in: directory).isEmpty, "no migration folder may be created on a preflight abort")
        try expectFalse(message.contains(directory.path), "the failure message must not include private paths")

        // No journal exists, so the directory is not locked: the legacy store
        // still reads exactly and the healthy current store saves normally.
        try makeFixture(.events).assertLoaded(persistence)
        try persistence.saveManifests([:])
    }

    /// A backup write failure stops the migration with every store file
    /// untouched; an explicit retry resumes and completes.
    func backupWriteFailureLeavesOriginalsUntouchedAndResumes() throws {
        let directory = Fixtures.makeTempDirectory("migr-backup-fail")
        let originals = try writeLegacyFiles([.events, .corrections], in: directory)
        let injector = MigrationFailureInjector()
        injector.shouldFail = { call in
            call.kind == .write
                && call.url.pathComponents.contains(PersistenceController.migrationBackupsFolderName)
                && call.url.lastPathComponent == StoreName.events.fileName
        }
        let persistence = PersistenceController(directory: directory, migrationFiles: injector)

        let failed = persistence.migrateLegacyStores()
        try expectMigrationFailed(failed, "backup write failure")
        for (store, bytes) in originals {
            try expectEqual(try Data(contentsOf: storeURL(directory, store)), bytes, "\(store.rawValue): original untouched")
        }
        let interruptedManifest = try readManifest(folder: try migrationFolders(in: directory)[0])
        try expectEqual(interruptedManifest.status, StoreMigrationProgress.backingUp)

        injector.shouldFail = { _ in false }
        let resumed = persistence.migrateLegacyStores()
        guard case .migrated = resumed else {
            throw TestFailure("expected the retry to complete, got \(resumed)")
        }
        try makeFixture(.events).assertLoaded(persistence)
        try makeFixture(.corrections).assertLoaded(persistence)
    }

    /// A staged envelope write failure stops the migration before any store
    /// file is replaced; an explicit retry resumes and completes.
    func stagedWriteFailureLeavesOriginalsUntouchedAndResumes() throws {
        let directory = Fixtures.makeTempDirectory("migr-staged-fail")
        let originals = try writeLegacyFiles([.events, .corrections], in: directory)
        let injector = MigrationFailureInjector()
        injector.shouldFail = { call in
            call.kind == .write && call.url.lastPathComponent == "staged-" + StoreName.events.fileName
        }
        let persistence = PersistenceController(directory: directory, migrationFiles: injector)

        let failed = persistence.migrateLegacyStores()
        try expectMigrationFailed(failed, "staged write failure")
        for (store, bytes) in originals {
            try expectEqual(try Data(contentsOf: storeURL(directory, store)), bytes, "\(store.rawValue): original untouched before any replacement")
        }

        injector.shouldFail = { _ in false }
        guard case .migrated = persistence.migrateLegacyStores() else {
            throw TestFailure("expected the retry to complete")
        }
        try makeFixture(.events).assertLoaded(persistence)
        try makeFixture(.corrections).assertLoaded(persistence)
    }

    /// Interrupting a replacement mid-apply leaves a detectable mixed
    /// generation; retrying the same migration verifies the bytes, applies
    /// the remaining stores, and completes with every payload intact.
    func replacementFailureInterruptsThenRetryCompletes() throws {
        let directory = Fixtures.makeTempDirectory("migr-replace-fail")
        let originals = try writeLegacyFiles(StoreName.allCases, in: directory)
        let injector = MigrationFailureInjector()
        injector.shouldFail = failReplacementOf(.reports)
        let persistence = PersistenceController(directory: directory, migrationFiles: injector)

        let failed = persistence.migrateLegacyStores()
        try expectMigrationFailed(failed, "replacement failure")

        // Detectable partial state: earlier participants are migrated
        // envelopes, later ones are still the exact legacy bytes.
        try assertEnvelope(try Data(contentsOf: storeURL(directory, .events)), store: .events, context: "events after interruption")
        try assertEnvelope(try Data(contentsOf: storeURL(directory, .corrections)), store: .corrections, context: "corrections after interruption")
        try expectEqual(try Data(contentsOf: storeURL(directory, .reports)), originals[.reports]!, "reports must still be the legacy original")
        try expectEqual(try Data(contentsOf: storeURL(directory, .settings)), originals[.settings]!, "settings must still be the legacy original")
        try expectEqual(try Data(contentsOf: storeURL(directory, .manifests)), originals[.manifests]!, "manifests must still be the legacy original")

        injector.shouldFail = { _ in false }
        guard case .migrated = persistence.migrateLegacyStores() else {
            throw TestFailure("expected the retry to complete")
        }
        for store in StoreName.allCases {
            try makeFixture(store).assertLoaded(persistence)
        }
        let manifest = try readManifest(folder: try migrationFolders(in: directory)[0])
        try expectEqual(manifest.status, StoreMigrationProgress.complete)
    }

    /// While a migration is partially applied, ordinary reads fail typed and
    /// ordinary saves are blocked for every store, so no mixed generation can
    /// be consumed or written. Completing the migration lifts the lock.
    func partialMigrationBlocksOrdinaryReadsAndSaves() throws {
        let directory = Fixtures.makeTempDirectory("migr-lock")
        try writeLegacyFiles(StoreName.allCases, in: directory)
        let injector = MigrationFailureInjector()
        injector.shouldFail = failReplacementOf(.reports)
        let persistence = PersistenceController(directory: directory, migrationFiles: injector)
        try expectMigrationFailed(persistence.migrateLegacyStores(), "interruption setup")

        for probe in ["events", "reports"] {
            let health: StoreFailure?
            switch probe {
            case "events":
                if case .failed(let failure) = persistence.loadEventsHealth() { health = failure } else { health = nil }
            default:
                if case .failed(let failure) = persistence.loadReportsHealth() { health = failure } else { health = nil }
            }
            let failure = try require(health, "\(probe): expected a typed failure while the migration is in progress")
            try expectTrue(failure.userMessage.contains("migration is in progress"), "\(probe): expected the migration message, got: \(failure.userMessage)")
            try expectFalse(failure.userMessage.contains(directory.path), "\(probe): the message must not include private paths")
        }

        do {
            _ = try persistence.loadEvents()
            throw TestFailure("the throwing load must fail while the migration is in progress")
        } catch let rejection as StoreFileRejection {
            try expectEqual(rejection, StoreFileRejection.migrationInProgress)
        }

        do {
            try persistence.saveEvents([syntheticEvent(id: "blocked")])
            throw TestFailure("an ordinary save must be blocked while the migration is in progress")
        } catch let rejection as StoreFileRejection {
            try expectEqual(rejection, StoreFileRejection.migrationInProgress)
        }

        guard case .failed(let recoveryMessage) = persistence.recoverStore(.events) else {
            throw TestFailure("recovery must be refused while the migration is in progress")
        }
        try expectTrue(recoveryMessage.contains("migration is in progress"), "recovery must name the in-progress migration")

        injector.shouldFail = { _ in false }
        guard case .migrated = persistence.migrateLegacyStores() else {
            throw TestFailure("expected the retry to complete")
        }
        try persistence.saveEvents([syntheticEvent(id: "after")])
        try expectEqual(try persistence.loadEvents().count, 1, "the blocked change was not saved; a fresh save works after completion")
    }

    /// Rolling back a completed migration restores every store to its exact
    /// legacy original bytes, keeps the backups and manifest with a
    /// rolled-back status, and leaves the legacy stores read-only again.
    func rollbackRestoresOriginalLegacyBytes() throws {
        let directory = Fixtures.makeTempDirectory("migr-rollback")
        let originals = try writeLegacyFiles(StoreName.allCases, in: directory)
        let persistence = PersistenceController(directory: directory)
        let migrated = persistence.migrateLegacyStores()
        guard case .migrated(let id, _) = migrated else {
            throw TestFailure("expected the migration to complete, got \(migrated)")
        }

        let outcome = persistence.rollbackLegacyStoreMigration()
        guard case .rolledBack(let rolledBackID, let stores) = outcome else {
            throw TestFailure("expected a rolled-back outcome, got \(outcome)")
        }
        try expectEqual(rolledBackID, id, "the rollback reports the same migration identity")
        try expectEqual(stores, Array(StoreName.allCases))

        for (store, bytes) in originals {
            try expectEqual(try Data(contentsOf: storeURL(directory, store)), bytes, "\(store.rawValue): rollback must restore the exact original bytes")
            try makeFixture(store).assertLoaded(persistence)
        }

        let folders = try migrationFolders(in: directory)
        try expectEqual(folders.count, 1, "backups are retained after rollback")
        let manifest = try readManifest(folder: folders[0])
        try expectEqual(manifest.status, StoreMigrationProgress.rolledBack)
        for backup in try FileManager.default.contentsOfDirectory(at: folders[0], includingPropertiesForKeys: nil)
        where backup.lastPathComponent != StoreMigrationManifest.fileName
            && !backup.lastPathComponent.hasPrefix(StoreMigrationEngine.stagedPrefix) {
            let store = StoreName(rawValue: backup.lastPathComponent.replacingOccurrences(of: ".json", with: ""))
            try expectTrue(store != nil, "backup \(backup.lastPathComponent) maps to a store")
            try expectEqual(try Data(contentsOf: backup), originals[store!], "the retained backup still holds the original bytes")
        }

        // Rollback lifts the lock, but the restored stores are legacy again:
        // ordinary saves stay rejected until the next explicit migration.
        do {
            try persistence.saveEvents([])
            throw TestFailure("an ordinary save over a restored legacy store must stay rejected")
        } catch let rejection as StoreFileRejection {
            try expectEqual(rejection, StoreFileRejection.legacyNeedsMigration)
        }
    }

    /// An interrupted rollback is journaled and detectable; retrying it
    /// restores the remaining stores to the exact original bytes.
    func rollbackInterruptionRetriesSafely() throws {
        let directory = Fixtures.makeTempDirectory("migr-rollback-fail")
        let originals = try writeLegacyFiles(StoreName.allCases, in: directory)
        let injector = MigrationFailureInjector()
        let persistence = PersistenceController(directory: directory, migrationFiles: injector)
        let migrated = persistence.migrateLegacyStores()
        guard case .migrated = migrated else {
            throw TestFailure("expected the migration to complete, got \(migrated)")
        }

        injector.shouldFail = failRollbackRestoreOf(.reports)
        let failed = persistence.rollbackLegacyStoreMigration()
        try expectMigrationFailed(failed, "rollback interruption")

        try expectEqual(try Data(contentsOf: storeURL(directory, .events)), originals[.events]!, "events was restored before the interruption")
        try expectEqual(try Data(contentsOf: storeURL(directory, .corrections)), originals[.corrections]!, "corrections was restored before the interruption")
        let interruptedManifest = try readManifest(folder: try migrationFolders(in: directory)[0])
        try expectEqual(interruptedManifest.status, StoreMigrationProgress.rollingBack)

        injector.shouldFail = { _ in false }
        guard case .rolledBack = persistence.rollbackLegacyStoreMigration() else {
            throw TestFailure("expected the rollback retry to complete")
        }
        for (store, bytes) in originals {
            try expectEqual(try Data(contentsOf: storeURL(directory, store)), bytes, "\(store.rawValue): the retry must restore the exact original bytes")
        }
        let manifest = try readManifest(folder: try migrationFolders(in: directory)[0])
        try expectEqual(manifest.status, StoreMigrationProgress.rolledBack)
    }

    /// Externally changed bytes are never overwritten: a hash that matches
    /// neither the recorded original nor the migrated target blocks both a
    /// migration retry and a rollback, preserving every byte.
    func externalByteChangeBlocksRetryAndRollbackWithoutOverwrite() throws {
        let directory = Fixtures.makeTempDirectory("migr-external")
        let originals = try writeLegacyFiles(StoreName.allCases, in: directory)
        let injector = MigrationFailureInjector()
        injector.shouldFail = failReplacementOf(.reports)
        let persistence = PersistenceController(directory: directory, migrationFiles: injector)
        try expectMigrationFailed(persistence.migrateLegacyStores(), "interruption setup")

        let tampered = (try Data(contentsOf: storeURL(directory, .settings))) + Data("external".utf8)
        try tampered.write(to: storeURL(directory, .settings))
        let tamperedEvents = (try Data(contentsOf: storeURL(directory, .events))) + Data("external".utf8)
        try tamperedEvents.write(to: storeURL(directory, .events))

        let retry = persistence.migrateLegacyStores()
        let retryMessage = try expectMigrationFailed(retry, "retry over external changes")
        try expectTrue(retryMessage.contains("changed outside this migration"), "the message must describe the outside change, got: \(retryMessage)")

        let rollback = persistence.rollbackLegacyStoreMigration()
        try expectMigrationFailed(rollback, "rollback over external changes")

        try expectEqual(try Data(contentsOf: storeURL(directory, .settings)), tampered, "the externally changed file must not be overwritten")
        try expectEqual(try Data(contentsOf: storeURL(directory, .events)), tamperedEvents, "the externally changed envelope must not be overwritten")
        try expectEqual(try Data(contentsOf: storeURL(directory, .reports)), originals[.reports]!, "unaffected stores stay untouched")
        let manifest = try readManifest(folder: try migrationFolders(in: directory)[0])
        try expectEqual(manifest.status, StoreMigrationProgress.applying, "the journal is preserved for a decision")
    }

    /// A second migration call after completion is an idempotent no-op: no
    /// new backups, no journal churn, and no byte changes anywhere.
    func repeatedMigrationAfterCompleteIsIdempotent() throws {
        let directory = Fixtures.makeTempDirectory("migr-idempotent")
        try writeLegacyFiles(StoreName.allCases, in: directory)
        let persistence = PersistenceController(directory: directory)
        let migrated = persistence.migrateLegacyStores()
        guard case .migrated = migrated else {
            throw TestFailure("expected the migration to complete, got \(migrated)")
        }

        let filesAfterFirst = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { !$0.hasDirectoryPath }
            .reduce(into: [String: Data]()) { result, url in result[url.lastPathComponent] = try Data(contentsOf: url) }
        let manifestAfterFirst = try Data(contentsOf: try migrationFolders(in: directory)[0].appendingPathComponent(StoreMigrationManifest.fileName))

        let second = persistence.migrateLegacyStores()
        try expectEqual(second, StoreMigrationOutcome.alreadyCurrent, "the repeat must be a no-op")

        try expectEqual(try migrationFolders(in: directory).count, 1, "no new migration folder is created")
        try expectEqual(try Data(contentsOf: try migrationFolders(in: directory)[0].appendingPathComponent(StoreMigrationManifest.fileName)), manifestAfterFirst, "the manifest is untouched by the repeat")
        let filesAfterSecond = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { !$0.hasDirectoryPath }
            .reduce(into: [String: Data]()) { result, url in result[url.lastPathComponent] = try Data(contentsOf: url) }
        try expectEqual(filesAfterSecond, filesAfterFirst, "no store file changes on the repeat")
    }

    /// The manifest records structural facts only: store identities, hashes,
    /// and relative backup names — never payload contents, absolute paths, or
    /// transcript strings. Recorded hashes match the actual bytes.
    func manifestRecordsHashesAndRelativeNamesWithoutPayloadOrPaths() throws {
        let directory = Fixtures.makeTempDirectory("migr-manifest-privacy")
        let originals = try writeLegacyFiles(StoreName.allCases, in: directory)
        let persistence = PersistenceController(directory: directory)
        let migrated = persistence.migrateLegacyStores()
        guard case .migrated = migrated else {
            throw TestFailure("expected the migration to complete, got \(migrated)")
        }

        let folder = try migrationFolders(in: directory)[0]
        let manifestURL = folder.appendingPathComponent(StoreMigrationManifest.fileName)
        let raw = String(decoding: try Data(contentsOf: manifestURL), as: UTF8.self)

        for store in StoreName.allCases {
            try expectTrue(raw.contains("\"\(store.rawValue)\""), "the manifest must record the \(store.rawValue) identity")
            try expectTrue(raw.contains(store.fileName), "the manifest must record the relative backup name \(store.fileName)")
            try expectFalse(raw.contains(String(decoding: originals[store]!, as: UTF8.self).prefix(40)), "the manifest must not embed \(store.rawValue) payload content")
        }
        try expectTrue(raw.contains("migrationID"), "the manifest must record the migration identity")
        try expectTrue(raw.contains("originalHash") && raw.contains("targetHash"), "the manifest must record byte hashes")
        try expectFalse(raw.contains(directory.path), "the manifest must not contain absolute paths")

        let manifest = try readManifest(folder: folder)
        for record in manifest.stores {
            try expectEqual(record.originalHash.count, 64, "original hashes are SHA-256 hex")
            try expectEqual(record.targetHash.count, 64, "target hashes are SHA-256 hex")
            let backupBytes = try Data(contentsOf: folder.appendingPathComponent(record.backupPath))
            try expectEqual(record.originalHash, StoreFileHashing.sha256Hex(backupBytes), "the recorded original hash matches the retained backup")
            let store = try require(StoreName(rawValue: record.store), "recorded store identity must parse")
            let migratedBytes = try Data(contentsOf: storeURL(directory, store))
            try expectEqual(record.targetHash, StoreFileHashing.sha256Hex(migratedBytes), "the recorded target hash matches the migrated file")
            try expectTrue(record.backupVerified, "every backup must be journaled verified")
        }
    }

    static var entries: [TestEntry] {
        let tests = PersistenceMigrationTests()
        return [
            TestEntry(suite: suiteName, name: "migrationUpgradesAllSixLegacyStoresAndRetainsVerifiedBackups") {
                try tests.migrationUpgradesAllSixLegacyStoresAndRetainsVerifiedBackups()
            },
            TestEntry(suite: suiteName, name: "migrationIsNoOpForCurrentAndMissingStores") {
                try tests.migrationIsNoOpForCurrentAndMissingStores()
            },
            TestEntry(suite: suiteName, name: "preflightRejectionsAbortBeforeAnyByteChanges") {
                try tests.preflightRejectionsAbortBeforeAnyByteChanges()
            },
            TestEntry(suite: suiteName, name: "backupWriteFailureLeavesOriginalsUntouchedAndResumes") {
                try tests.backupWriteFailureLeavesOriginalsUntouchedAndResumes()
            },
            TestEntry(suite: suiteName, name: "stagedWriteFailureLeavesOriginalsUntouchedAndResumes") {
                try tests.stagedWriteFailureLeavesOriginalsUntouchedAndResumes()
            },
            TestEntry(suite: suiteName, name: "replacementFailureInterruptsThenRetryCompletes") {
                try tests.replacementFailureInterruptsThenRetryCompletes()
            },
            TestEntry(suite: suiteName, name: "partialMigrationBlocksOrdinaryReadsAndSaves") {
                try tests.partialMigrationBlocksOrdinaryReadsAndSaves()
            },
            TestEntry(suite: suiteName, name: "rollbackRestoresOriginalLegacyBytes") {
                try tests.rollbackRestoresOriginalLegacyBytes()
            },
            TestEntry(suite: suiteName, name: "rollbackInterruptionRetriesSafely") {
                try tests.rollbackInterruptionRetriesSafely()
            },
            TestEntry(suite: suiteName, name: "externalByteChangeBlocksRetryAndRollbackWithoutOverwrite") {
                try tests.externalByteChangeBlocksRetryAndRollbackWithoutOverwrite()
            },
            TestEntry(suite: suiteName, name: "repeatedMigrationAfterCompleteIsIdempotent") {
                try tests.repeatedMigrationAfterCompleteIsIdempotent()
            },
            TestEntry(suite: suiteName, name: "manifestRecordsHashesAndRelativeNamesWithoutPayloadOrPaths") {
                try tests.manifestRecordsHashesAndRelativeNamesWithoutPayloadOrPaths()
            }
        ]
    }
}
