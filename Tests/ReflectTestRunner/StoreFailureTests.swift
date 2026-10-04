import Foundation
@testable import ReflectLib

/// Regression coverage for damaged-store handling. Every fixture is synthetic
/// and lives in a fresh temporary directory; no real user data is ever read.
struct StoreFailureTests {
    static let suiteName = "StoreFailureTests"

    private func syntheticReport(day: String) -> DailyReport {
        DailyReport(
            day: day,
            narrative: "",
            narrativeGeneratedAt: nil,
            answers: [:],
            analysisResult: nil,
            analysisGeneratedAt: nil,
            updatedAt: Fixtures.referenceDate
        )
    }

    @MainActor
    private func makeAppStore(directory: URL) -> AppStore {
        AppStore(
            persistence: PersistenceController(directory: directory),
            secrets: MemorySecretStore(),
            home: Fixtures.makeTempDirectory(directory.lastPathComponent + "-home"),
            analysisAvailabilityProvider: { @Sendable () async -> [AnalysisAgentStatus] in [] }
        )
    }

    /// A reports store file that exists but cannot be decoded must never be
    /// overwritten by the ordinary report save path, and that save must not
    /// claim success.
    @MainActor
    func malformedReportsStoreIsNotOverwrittenByOrdinarySave() throws {
        let directory = Fixtures.makeTempDirectory("store-malformed-reports")
        let reportsURL = directory.appendingPathComponent("reports.json")
        let original = Data("{\"reports\": [ {\"synthetic-damaged-fixture\":".utf8)
        try original.write(to: reportsURL)

        let store = makeAppStore(directory: directory)
        let accepted = store.saveReport(syntheticReport(day: "2026-01-05"))

        let after = try Data(contentsOf: reportsURL)
        try expectEqual(after, original, "an ordinary save must not overwrite damaged store bytes")
        try expectFalse(accepted, "an ordinary save over a damaged store must not claim success")
    }

    /// An events store file that exists but cannot be decoded must never be
    /// replaced by the ordinary events save path.
    @MainActor
    func malformedEventsStoreIsNotOverwrittenByOrdinarySave() throws {
        let directory = Fixtures.makeTempDirectory("store-malformed-events")
        let eventsURL = directory.appendingPathComponent("events.json")
        let original = Data("{\"events\": [ {\"synthetic-damaged-fixture\":".utf8)
        try original.write(to: eventsURL)

        let store = makeAppStore(directory: directory)
        store.persistEvents()

        let after = try Data(contentsOf: eventsURL)
        try expectEqual(after, original, "an ordinary save must not overwrite damaged store bytes")
    }

    /// An absent store is a valid first-run state: no failure, and the first
    /// ordinary save simply creates the file.
    @MainActor
    func missingStoreAllowsFirstSave() throws {
        let directory = Fixtures.makeTempDirectory("store-missing")
        let persistence = PersistenceController(directory: directory)

        guard case .missing = persistence.loadSettingsHealth() else {
            throw TestFailure("expected .missing for an absent settings store")
        }
        guard case .missing = persistence.loadEventsHealth() else {
            throw TestFailure("expected .missing for an absent events store")
        }

        let store = makeAppStore(directory: directory)
        try expectTrue(store.storeFailures.isEmpty, "an absent store must not be recorded as failed")

        store.persistSettings()
        try expectTrue(
            FileManager.default.fileExists(atPath: directory.appendingPathComponent("settings.json").path),
            "the first save must create the missing store file"
        )
        guard case .loaded(let loadedSettings) = persistence.loadSettingsHealth() else {
            throw TestFailure("expected a valid loaded settings store after the first save")
        }
        try expectEqual(loadedSettings, AppSettings.default())
        try expectTrue(store.storeFailures.isEmpty, "first-run saving must not turn into a failure state")
    }

    /// A store file that exists but cannot be decoded is recorded as failed,
    /// never silently defaulted, and loading of the other stores stays
    /// independent.
    @MainActor
    func malformedStoreIsNotEmptySuccess() throws {
        let directory = Fixtures.makeTempDirectory("store-malformed-health")
        let persistence = PersistenceController(directory: directory)
        try persistence.saveReports([syntheticReport(day: "2026-01-05")])
        let damagedBytes = Data("{\"events\": [ {\"synthetic-damaged-fixture\":".utf8)
        try damagedBytes.write(to: directory.appendingPathComponent("events.json"))

        let store = makeAppStore(directory: directory)

        let failure = try require(
            store.storeFailures[.events],
            "a damaged store must be recorded as failed, not silently defaulted to empty"
        )
        try expectEqual(failure.store, StoreName.events)
        try expectFalse(failure.userMessage.contains(directory.path), "the failure message must not include private paths")
        try expectFalse(failure.userMessage.contains("synthetic-damaged-fixture"), "the failure message must not include damaged bytes")

        // A failure in one store must not fail the others.
        try expectNil(store.storeFailures[.reports], "healthy stores stay healthy when a sibling store is damaged")
        try expectEqual(store.reports.count, 1, "the healthy reports store still loads its content")
        try expectEqual(store.reports.first?.day, "2026-01-05")

        // The typed health result stays failed even though published events are empty.
        guard case .failed = persistence.loadEventsHealth() else {
            throw TestFailure("expected the events store health to stay failed after load")
        }
        try expectTrue(store.events.isEmpty, "damaged content is not rendered as if it were data")
    }

    /// A file that exists but cannot be read is a failure state; ordinary
    /// saves to that store are rejected and healthy stores keep writing.
    @MainActor
    func unreadableStoreBlocksReplacement() throws {
        let directory = Fixtures.makeTempDirectory("store-unreadable")
        let eventsURL = directory.appendingPathComponent("events.json")
        let original = Data("[\"synthetic-unreadable-fixture\"]".utf8)
        try original.write(to: eventsURL)
        let fileManager = FileManager.default
        try fileManager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: eventsURL.path)
        defer { try? fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: eventsURL.path) }

        let store = makeAppStore(directory: directory)
        try expectTrue(
            store.storeFailures[.events] != nil,
            "a file that exists but cannot be read is a failure, not first run"
        )

        store.persistEvents()
        try expectTrue(store.lastError != nil, "a blocked write must surface an error")

        try? fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: eventsURL.path)
        let after = try Data(contentsOf: eventsURL)
        try expectEqual(after, original, "a blocked write must not alter the original bytes")

        // Healthy stores keep writing while the events store is damaged.
        let saved = store.saveReport(syntheticReport(day: "2026-01-06"))
        try expectTrue(saved, "healthy stores must keep writing when another store is damaged")
        try expectNil(store.storeFailures[.reports], "the reports store stays healthy")
    }

    /// Every damaged store blocks exactly its own ordinary write path, and a
    /// rejected write never alters the damaged bytes on disk. The `sessions`
    /// store is deliberately not loaded at launch (only the explicit session
    /// import path reads it), so its damaged-file behavior is verified at the
    /// persistence layer instead of through AppStore state.
    @MainActor
    func damagedStoreBlocksItsOwnOrdinaryWrites() throws {
        for storeName in StoreName.allCases {
            let directory = Fixtures.makeTempDirectory("store-blocked-\(storeName.rawValue)")
            let storeURL = directory.appendingPathComponent(storeName.fileName)
            let original = Data("synthetic damaged bytes for \(storeName.rawValue)".utf8)
            try original.write(to: storeURL)

            let store = makeAppStore(directory: directory)
            if storeName != .sessions && storeName != .conversations {
                guard store.storeFailures[storeName] != nil else {
                    throw TestFailure("\(storeName): expected a recorded failure for the damaged store")
                }
            }
            let before = try Data(contentsOf: storeURL)

            switch storeName {
            case .events: store.persistEvents()
            case .corrections: store.setCorrection(.agent, for: "fixture-event-1")
            case .reports:
                let accepted = store.saveReport(syntheticReport(day: "2026-01-05"))
                try expectFalse(accepted, "\(storeName): the ordinary write must be rejected")
            case .settings: store.persistSettings()
            case .manifests: store.persistManifests()
            case .sessions:
                try expectNil(store.storeFailures[.sessions], "sessions must not be read or failed at launch")
                let persistence = PersistenceController(directory: directory)
                guard case .failed(let failure) = persistence.loadSessionsHealth() else {
                    throw TestFailure("sessions: expected a typed failure for the damaged store")
                }
                try expectFalse(failure.userMessage.contains(directory.path), "the failure message must not include private paths")
                do {
                    try persistence.saveSessions([])
                    throw TestFailure("sessions: an ordinary save must be rejected over damaged bytes")
                } catch let rejection as StoreFileRejection {
                    try expectEqual(rejection, StoreFileRejection.malformed, "sessions: the rejection must be typed")
                }
            case .conversations:
                // The conversations store is owned by the conversation
                // service, never read at launch, so like sessions its
                // damaged-file behavior is verified at the persistence layer.
                try expectNil(store.storeFailures[.conversations], "conversations must not be read or failed at launch")
                let persistence = PersistenceController(directory: directory)
                guard case .failed(let failure) = persistence.loadConversationsHealth() else {
                    throw TestFailure("conversations: expected a typed failure for the damaged store")
                }
                try expectFalse(failure.userMessage.contains(directory.path), "the failure message must not include private paths")
                do {
                    try persistence.saveConversations([])
                    throw TestFailure("conversations: an ordinary save must be rejected over damaged bytes")
                } catch let rejection as StoreFileRejection {
                    try expectEqual(rejection, StoreFileRejection.malformed, "conversations: the rejection must be typed")
                }
            }

            if storeName != .sessions && storeName != .conversations {
                try expectTrue(store.lastError != nil, "\(storeName): a blocked write must surface an error")
            }
            let after = try Data(contentsOf: storeURL)
            try expectEqual(after, before, "\(storeName): a blocked write must not alter the original bytes")
            try expectEqual(before, original, "\(storeName): the damaged bytes must be intact")
        }
    }

    /// Successful recovery: the damaged bytes are preserved exactly in a backup
    /// inside the private store directory, a fresh valid store is installed,
    /// and the store becomes writable again.
    @MainActor
    func recoveryBacksUpOriginalBytesAndRestoresUsableStore() throws {
        let directory = Fixtures.makeTempDirectory("store-recover-success")
        let eventsURL = directory.appendingPathComponent("events.json")
        let original = Data("{\"events\": [ {\"synthetic-damaged-fixture\":".utf8)
        try original.write(to: eventsURL)

        let store = makeAppStore(directory: directory)
        guard store.storeFailures[.events] != nil else {
            throw TestFailure("expected the damaged events store to be recorded as failed")
        }

        store.recoverStore(.events)

        try expectTrue(store.storeFailures.isEmpty, "successful recovery clears the failure state")
        try expectNil(store.lastRecoveryMessage, "successful recovery must not look like a failure")

        let backups = directory.appendingPathComponent("Damaged Backups", isDirectory: true)
        let backupFiles = try FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
        try expectEqual(backupFiles.count, 1, "exactly one backup is created")
        let backupBytes = try Data(contentsOf: backupFiles[0])
        try expectEqual(backupBytes, original, "the backup must preserve the damaged bytes exactly")

        let persistence = PersistenceController(directory: directory)
        guard case .loaded(let events) = persistence.loadEventsHealth() else {
            throw TestFailure("expected a valid loaded store after recovery")
        }
        try expectTrue(events.isEmpty, "the recovered store starts as a valid default")

        store.persistEvents()
        try expectNil(store.lastError, "ordinary writes work again after recovery")

        // End to end: save real content, reopen the store, and load it.
        try persistence.saveEvents([Fixtures.dayEvents(count: 1).first!])
        let reopened = makeAppStore(directory: directory)
        try expectEqual(reopened.events.count, 1, "a store recovered once must accept new content")
        try expectTrue(reopened.storeFailures.isEmpty, "the reopened store is healthy")
    }

    /// Backup failure: recovery stops before changing anything, keeps the
    /// failure state, and leaves the original bytes intact.
    func backupFailureKeepsFailureStateAndOriginalBytes() throws {
        let directory = Fixtures.makeTempDirectory("store-recover-backup-fail")
        let settingsURL = directory.appendingPathComponent("settings.json")
        let original = Data("synthetic damaged settings bytes".utf8)
        try original.write(to: settingsURL)

        let persistence = PersistenceController(directory: directory)
        let fileManager = FileManager.default
        try fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }

        let outcome = persistence.recoverStore(.settings)

        guard case .failed(let message) = outcome else {
            throw TestFailure("expected a failed recovery outcome, got \(outcome)")
        }
        try expectFalse(message.contains(directory.path), "recovery failures must not expose private paths")
        try expectTrue(message.contains("untouched"), "the message must say the original file is untouched")

        let after = try Data(contentsOf: settingsURL)
        try expectEqual(after, original, "a failed backup must not alter the original bytes")
        let backups = directory.appendingPathComponent("Damaged Backups", isDirectory: true)
        try expectFalse(
            fileManager.fileExists(atPath: backups.path),
            "no backup may be claimed when the backup could not be created"
        )
        guard case .failed = persistence.loadSettingsHealth() else {
            throw TestFailure("the store must stay failed after a failed recovery")
        }
    }

    /// Replacement failure: the backup exists and preserves the original bytes,
    /// the damaged file is untouched, and a later recovery still succeeds.
    func failedReplacementKeepsOriginalRecoverable() throws {
        let directory = Fixtures.makeTempDirectory("store-recover-replace-fail")
        let eventsURL = directory.appendingPathComponent("events.json")
        let original = Data("{\"events\": [ {\"synthetic-damaged-fixture\":".utf8)
        try original.write(to: eventsURL)

        let fileManager = FileManager.default
        let backups = directory.appendingPathComponent("Damaged Backups", isDirectory: true)
        try fileManager.createDirectory(at: backups, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)

        let persistence = PersistenceController(directory: directory)
        let outcome = persistence.recoverStore(.events)

        guard case .failed(let message) = outcome else {
            throw TestFailure("expected a failed recovery outcome, got \(outcome)")
        }
        try expectFalse(message.contains(directory.path), "recovery failures must not expose private paths")

        let backupFiles = try fileManager.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
        try expectEqual(backupFiles.count, 1, "the backup from the failed attempt must exist")
        try expectEqual(try Data(contentsOf: backupFiles[0]), original, "the backup preserves the original bytes")
        try expectEqual(try Data(contentsOf: eventsURL), original, "the damaged file is untouched after a failed replacement")
        guard case .failed = persistence.loadEventsHealth() else {
            throw TestFailure("the store must stay failed when the replacement could not be installed")
        }

        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        defer { try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }

        let second = persistence.recoverStore(.events)
        guard case .recovered = second else {
            throw TestFailure("the original must remain recoverable after a failed attempt, got \(second)")
        }
        let backupFilesAfter = try fileManager.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
        try expectEqual(backupFilesAfter.count, 2, "each recovery attempt keeps its own backup")
        for backup in backupFilesAfter {
            try expectEqual(try Data(contentsOf: backup), original, "every backup preserves the original bytes")
        }
        guard case .loaded(let events) = persistence.loadEventsHealth() else {
            throw TestFailure("expected a valid loaded store after the successful recovery")
        }
        try expectTrue(events.isEmpty, "the recovered store starts as a valid default")
    }

    /// A failed recovery keeps the AppStore failure state and surfaces a safe
    /// message; it never presents itself as successful.
    @MainActor
    func failedRecoveryKeepsAppStoreFailureState() throws {
        let directory = Fixtures.makeTempDirectory("store-recover-appstate")
        let eventsURL = directory.appendingPathComponent("events.json")
        let original = Data("{\"events\": [ {\"synthetic-damaged-fixture\":".utf8)
        try original.write(to: eventsURL)

        let fileManager = FileManager.default
        let backups = directory.appendingPathComponent("Damaged Backups", isDirectory: true)
        try fileManager.createDirectory(at: backups, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }

        let store = makeAppStore(directory: directory)
        store.recoverStore(.events)

        try expectTrue(store.storeFailures[.events] != nil, "failed recovery must keep the failure state")
        let message = try require(store.lastRecoveryMessage, "failed recovery must surface a safe message")
        try expectFalse(message.contains(directory.path), "recovery messages must not expose private paths")
        try expectEqual(try Data(contentsOf: eventsURL), original, "the damaged bytes stay intact")
    }

    static var entries: [TestEntry] {
        let tests = StoreFailureTests()
        return [
            TestEntry(suite: suiteName, name: "malformedReportsStoreIsNotOverwrittenByOrdinarySave") {
                try MainActor.assumeIsolated { try tests.malformedReportsStoreIsNotOverwrittenByOrdinarySave() }
            },
            TestEntry(suite: suiteName, name: "malformedEventsStoreIsNotOverwrittenByOrdinarySave") {
                try MainActor.assumeIsolated { try tests.malformedEventsStoreIsNotOverwrittenByOrdinarySave() }
            },
            TestEntry(suite: suiteName, name: "missingStoreAllowsFirstSave") {
                try MainActor.assumeIsolated { try tests.missingStoreAllowsFirstSave() }
            },
            TestEntry(suite: suiteName, name: "malformedStoreIsNotEmptySuccess") {
                try MainActor.assumeIsolated { try tests.malformedStoreIsNotEmptySuccess() }
            },
            TestEntry(suite: suiteName, name: "unreadableStoreBlocksReplacement") {
                try MainActor.assumeIsolated { try tests.unreadableStoreBlocksReplacement() }
            },
            TestEntry(suite: suiteName, name: "damagedStoreBlocksItsOwnOrdinaryWrites") {
                try MainActor.assumeIsolated { try tests.damagedStoreBlocksItsOwnOrdinaryWrites() }
            },
            TestEntry(suite: suiteName, name: "recoveryBacksUpOriginalBytesAndRestoresUsableStore") {
                try MainActor.assumeIsolated { try tests.recoveryBacksUpOriginalBytesAndRestoresUsableStore() }
            },
            TestEntry(suite: suiteName, name: "backupFailureKeepsFailureStateAndOriginalBytes") {
                try tests.backupFailureKeepsFailureStateAndOriginalBytes()
            },
            TestEntry(suite: suiteName, name: "failedReplacementKeepsOriginalRecoverable") {
                try tests.failedReplacementKeepsOriginalRecoverable()
            },
            TestEntry(suite: suiteName, name: "failedRecoveryKeepsAppStoreFailureState") {
                try MainActor.assumeIsolated { try tests.failedRecoveryKeepsAppStoreFailureState() }
            }
        ]
    }
}
