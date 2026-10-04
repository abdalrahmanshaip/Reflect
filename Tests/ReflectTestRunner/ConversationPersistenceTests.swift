import Foundation
@testable import ReflectLib

/// Awaits throwing async service work from a synchronous test entry.
private func awaitAsyncThrows<T: Sendable>(_ body: @escaping @Sendable () async throws -> T) throws -> T {
    let box = AsyncResultBox<Result<T, Error>>()
    Task.detached {
        do {
            box.fulfill(.success(try await body()))
        } catch {
            box.fulfill(.failure(error))
        }
    }
    guard box.semaphore.wait(timeout: .now() + 30) == .success else {
        throw TestFailure("async test work did not finish within 30s")
    }
    guard let result = box.take() else {
        throw TestFailure("async test work produced no result")
    }
    return try result.get()
}

/// M3 slice 1 coverage for the versioned `conversations` store integration:
/// the store is wired through `PersistenceController` and the accepted
/// versioned envelope APIs (identity, determinism, fail-closed rejections,
/// explicit recovery, and explicit migration participation), and the
/// conversation service refuses to start on a damaged store. Every fixture
/// is synthetic and lives in a fresh temporary directory; no real store and
/// no source history is ever touched.
struct ConversationPersistenceTests {
    static let suiteName = "ConversationPersistenceTests"

    private let referenceDate = Date(timeIntervalSince1970: 1_767_614_400) // 2026-01-05T12:00:00Z

    // MARK: Helpers

    private func storeURL(_ directory: URL) -> URL {
        directory.appendingPathComponent(StoreName.conversations.fileName)
    }

    private func assertEnvelopeIdentity(_ data: Data) throws {
        let object = try require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
            "the conversations store must be a JSON envelope object"
        )
        try expectEqual(object["store"] as? String, "conversations", "the envelope must carry the conversations store identity")
        try expectEqual(object["schemaVersion"] as? Int, 1, "the conversations store is currently at schema version 1")
        try expectTrue(object["payload"] != nil, "the envelope must carry a payload")
    }

    private func readyConfiguration() -> StaticConversationConfiguration {
        StaticConversationConfiguration()
    }

    struct StaticConversationConfiguration: ConversationConfigurationProviding {
        func currentConfiguration() -> ConversationConfiguration {
            .ready(agentKind: .codex, selectedModel: nil)
        }
    }

    final class SilentFakeAgent: ConversationResponding, @unchecked Sendable {
        var callCount = 0
        private let lock = NSLock()
        func respond(to request: ConversationRequest, context: ContextEnvelope) async throws -> ConversationResponse {
            lock.lock()
            callCount += 1
            lock.unlock()
            return ConversationResponse(requestID: request.id, answerText: "Synthetic persistence answer.")
        }
    }

    private func makeService(_ persistence: PersistenceController, agent: SilentFakeAgent) throws -> ConversationService {
        try ConversationService(
            persistence: persistence,
            contextProvider: RetrievalConversationContextProvider(persistence: persistence),
            responder: agent,
            configuration: readyConfiguration()
        )
    }

    // MARK: Tests

    func conversationsStoreRoundTripsVersionOneEnvelopeDeterministically() throws {
        let directory = Fixtures.makeTempDirectory("convp-roundtrip")
        let persistence = PersistenceController(directory: directory)
        let fixture = Fixtures.syntheticStoredConversation()

        try persistence.saveConversations([fixture])
        try assertEnvelopeIdentity(try Data(contentsOf: storeURL(directory)))
        try expectEqual(try persistence.loadConversations(), [fixture])
        guard case .loaded(let healthValue) = persistence.loadConversationsHealth() else {
            throw TestFailure("expected a loaded conversations store")
        }
        try expectEqual(healthValue, [fixture])

        let firstBytes = try Data(contentsOf: storeURL(directory))
        try persistence.saveConversations([fixture])
        try expectEqual(try Data(contentsOf: storeURL(directory)), firstBytes, "equal payloads must encode to byte-identical version-1 envelopes")
    }

    func missingStoreIsFirstRunAndRecoveryInstallsFreshEnvelope() throws {
        let directory = Fixtures.makeTempDirectory("convp-missing")
        let persistence = PersistenceController(directory: directory)
        guard case .missing = persistence.loadConversationsHealth() else {
            throw TestFailure("an absent conversations store must load as missing, the valid first-run state")
        }

        // A damaged store is protected, recoverable, and never treated as empty.
        let damaged = Data("synthetic damaged conversations bytes".utf8)
        try damaged.write(to: storeURL(directory))
        guard case .failed(let failure) = persistence.loadConversationsHealth() else {
            throw TestFailure("a damaged conversations store must fail typed")
        }
        try expectFalse(failure.userMessage.contains(directory.path), "the failure message must not include private paths")

        try expectEqual(persistence.recoverStore(.conversations), StoreRecoveryOutcome.recovered)
        try assertEnvelopeIdentity(try Data(contentsOf: storeURL(directory)))
        try expectEqual(try persistence.loadConversations(), [] as [StoredConversation], "the recovered store is a valid default")
        try expectFalse(FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent(PersistenceController.damagedBackupsFolderName).path).isEmpty, "the damaged bytes must be preserved under Damaged Backups")
    }

    func damagedStoreFailsClosedAtPersistenceAndServiceLayers() throws {
        let directory = Fixtures.makeTempDirectory("convp-damaged")
        let persistence = PersistenceController(directory: directory)
        let original = Data("{\"synthetic-damaged-fixture\":".utf8)
        try original.write(to: storeURL(directory))

        do {
            try persistence.saveConversations([])
            throw TestFailure("an ordinary save over damaged bytes must be rejected")
        } catch let rejection as StoreFileRejection {
            try expectEqual(rejection, StoreFileRejection.malformed, "the rejection must be typed")
        }
        try expectEqual(try Data(contentsOf: storeURL(directory)), original, "a rejected save must not alter the damaged bytes")

        // The service refuses to start with a fake empty view of a damaged store.
        do {
            _ = try makeService(persistence, agent: SilentFakeAgent())
            throw TestFailure("the service must not start on a damaged conversations store")
        } catch let error as ConversationService.ServiceError {
            guard case .storeDamaged(let message) = error else { throw TestFailure("expected storeDamaged, got \(error)") }
            try expectFalse(message.contains(directory.path), "the service error must not include private paths")
        }
    }

    func wrongStoreAndNewerSchemaEnvelopesAreRejected() throws {
        let directory = Fixtures.makeTempDirectory("convp-rejections")
        let persistence = PersistenceController(directory: directory)

        let sessionsEnvelope = """
        {
          "payload" : [],
          "schemaVersion" : 1,
          "store" : "sessions"
        }
        """
        try sessionsEnvelope.data(using: .utf8)!.write(to: storeURL(directory))
        let before = try Data(contentsOf: storeURL(directory))
        guard case .failed(let wrongStore) = persistence.loadConversationsHealth() else {
            throw TestFailure("a wrong-store envelope must fail typed")
        }
        try expectTrue(wrongStore.userMessage.contains("different store"), "the failure must identify the mismatch honestly")
        do {
            try persistence.saveConversations([Fixtures.syntheticStoredConversation()])
            throw TestFailure("saving over a wrong-store file must be rejected")
        } catch let rejection as StoreFileRejection {
            guard case .wrongStore = rejection else { throw TestFailure("expected wrongStore, got \(rejection)") }
        }
        try expectEqual(try Data(contentsOf: storeURL(directory)), before, "rejected writes must leave the file untouched")

        let newerEnvelope = """
        {
          "payload" : [],
          "schemaVersion" : 2,
          "store" : "conversations"
        }
        """
        try newerEnvelope.data(using: .utf8)!.write(to: storeURL(directory))
        guard case .failed(let newer) = persistence.loadConversationsHealth() else {
            throw TestFailure("a newer-schema envelope must fail typed")
        }
        try expectTrue(newer.userMessage.contains("newer version"), "the failure must identify the unsupported schema honestly")
    }

    func legacyConversationsFileMigratesExplicitlyWithVerifiedBackup() throws {
        let directory = Fixtures.makeTempDirectory("convp-legacy")
        let legacyBytes = Data(Fixtures.syntheticConversationsLegacyJSON.utf8)
        try legacyBytes.write(to: storeURL(directory))

        // Ordinary saves refuse to replace a legacy bare file.
        let persistence = PersistenceController(directory: directory)
        do {
            try persistence.saveConversations([Fixtures.syntheticStoredConversation()])
            throw TestFailure("an ordinary save must not replace a legacy file before migration")
        } catch let rejection as StoreFileRejection {
            try expectEqual(rejection, StoreFileRejection.legacyNeedsMigration, "the legacy file must stay read-only until explicit migration")
        }
        try expectEqual(try Data(contentsOf: storeURL(directory)), legacyBytes, "the legacy original must be untouched")

        // The explicit migration upgrades it with a verified backup.
        guard case .migrated(_, let stores) = persistence.migrateLegacyStores() else {
            throw TestFailure("expected a migrated outcome")
        }
        try expectTrue(stores.contains(.conversations), "the conversations store must participate in explicit migration")
        let fixture = Fixtures.syntheticStoredConversation()
        try expectEqual(try persistence.loadConversations(), [fixture])
        try assertEnvelopeIdentity(try Data(contentsOf: storeURL(directory)))

        let folders = try FileManager.default.contentsOfDirectory(
            at: directory.appendingPathComponent(PersistenceController.migrationBackupsFolderName),
            includingPropertiesForKeys: nil
        )
        try expectEqual(folders.count, 1, "exactly one migration folder is created")
        let backup = try Data(contentsOf: folders[0].appendingPathComponent(StoreName.conversations.fileName))
        try expectEqual(backup, legacyBytes, "the backup must preserve the original legacy bytes exactly")
    }

    func absentConversationsStoreStaysAbsentThroughMigration() throws {
        let directory = Fixtures.makeTempDirectory("convp-absent")
        // An older installation has no conversations store at all; a legacy
        // events store alone participates in the migration.
        let legacyEvents = """
        [
          {
            "detail" : "Synthetic legacy preview text",
            "evidenceLine" : 42,
            "evidencePath" : "/tmp/fixture/legacy-session.jsonl",
            "id" : "fixture-legacy-event-1",
            "importedAt" : "2026-01-05T12:00:00Z",
            "kind" : "user_message",
            "observedAttribution" : "unclear",
            "observedAttributionNote" : "Structural role in transcript",
            "sourceKind" : "claude_code",
            "sourceName" : "Claude Code",
            "summary" : "Synthetic legacy event",
            "timestamp" : "2026-01-05T12:00:00Z",
            "timestampApproximate" : true
          }
        ]
        """
        try legacyEvents.data(using: .utf8)!.write(to: directory.appendingPathComponent(StoreName.events.fileName))

        let persistence = PersistenceController(directory: directory)
        guard case .migrated(_, let stores) = persistence.migrateLegacyStores() else {
            throw TestFailure("expected a migrated outcome")
        }
        try expectTrue(stores.contains(.events))
        try expectFalse(stores.contains(.conversations), "an absent conversations store must stay absent")
        try expectFalse(FileManager.default.fileExists(atPath: storeURL(directory).path), "migration must not invent a conversations store")
        guard case .missing = persistence.loadConversationsHealth() else {
            throw TestFailure("the conversations store must still be first-run after migration")
        }
    }

    func conversationActivityLeavesObservationStoresByteIdentical() throws {
        let directory = Fixtures.makeTempDirectory("convp-observation-stores")
        let persistence = PersistenceController(directory: directory)
        try persistence.saveSessions([Fixtures.syntheticSession()])
        try persistence.saveEvents([])
        try persistence.saveCorrections([])
        try persistence.saveReports([])

        func hashes() throws -> [String: String] {
            var result: [String: String] = [:]
            for store in StoreName.allCases where store != .conversations {
                let url = directory.appendingPathComponent(store.fileName)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                result[store.rawValue] = StoreFileHashing.sha256Hex(try Data(contentsOf: url))
            }
            return result
        }
        let before = try hashes()

        let agent = SilentFakeAgent()
        let service = try makeService(persistence, agent: agent)
        let conversation = try awaitAsyncThrows { try await service.createConversation() }
        _ = try awaitAsyncThrows { await service.send("Synthetic question about debugging.", in: conversation.id) }
        try expectEqual(agent.callCount, 1)

        try expectEqual(try hashes(), before, "conversation activity must never mutate observation stores")
        let conversations = try persistence.loadConversations()
        try expectEqual(conversations.count, 1)
        try expectEqual(conversations[0].messages.count, 2, "the conversation itself must be durably persisted in its own store")
    }

    static var entries: [TestEntry] {
        let tests = ConversationPersistenceTests()
        return [
            TestEntry(suite: suiteName, name: "conversationsStoreRoundTripsVersionOneEnvelopeDeterministically") {
                try tests.conversationsStoreRoundTripsVersionOneEnvelopeDeterministically()
            },
            TestEntry(suite: suiteName, name: "missingStoreIsFirstRunAndRecoveryInstallsFreshEnvelope") {
                try tests.missingStoreIsFirstRunAndRecoveryInstallsFreshEnvelope()
            },
            TestEntry(suite: suiteName, name: "damagedStoreFailsClosedAtPersistenceAndServiceLayers") {
                try tests.damagedStoreFailsClosedAtPersistenceAndServiceLayers()
            },
            TestEntry(suite: suiteName, name: "wrongStoreAndNewerSchemaEnvelopesAreRejected") {
                try tests.wrongStoreAndNewerSchemaEnvelopesAreRejected()
            },
            TestEntry(suite: suiteName, name: "legacyConversationsFileMigratesExplicitlyWithVerifiedBackup") {
                try tests.legacyConversationsFileMigratesExplicitlyWithVerifiedBackup()
            },
            TestEntry(suite: suiteName, name: "absentConversationsStoreStaysAbsentThroughMigration") {
                try tests.absentConversationsStoreStaysAbsentThroughMigration()
            },
            TestEntry(suite: suiteName, name: "conversationActivityLeavesObservationStoresByteIdentical") {
                try tests.conversationActivityLeavesObservationStoresByteIdentical()
            }
        ]
    }
}
