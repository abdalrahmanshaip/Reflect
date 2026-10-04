import Foundation

/// Small atomic JSON file persistence layer. Everything lives in the user's
/// Application Support/Reflect folder as human-readable JSON files. Each store
/// file is a versioned envelope (`StoreFileWriter`); legacy bare payloads from
/// before envelopes existed keep reading transparently as schema version 0,
/// and those legacy reads are strictly read-only until the store is migrated
/// by the explicit migration path.
struct JSONFileStore<T: Codable> {
    let url: URL
    let storeName: StoreName
    /// Returns true while an explicit migration or rollback is in progress.
    /// While locked, reads and ordinary saves are refused so the app can never
    /// consume or write a mixed on-disk generation; explicit retry, rollback,
    /// and completion of the migration are the only ways through.
    var mutationLocked: () -> Bool = { false }

    func load() throws -> T? {
        try guardNotLocked()
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try StoreFileReader.read(data, store: storeName, as: T.self)
    }

    /// Typed load outcome. `missing` is the valid first-run state; a file that
    /// exists but cannot be read, decoded, or accepted as this store's current
    /// or legacy schema is a failure that must never be treated as an empty
    /// store or silently defaulted.
    func loadHealth() -> StoreLoad<T> {
        if mutationLocked() {
            return .failed(StoreFailure(store: storeName, userMessage: StoreHealthMessages.migrationInProgress(storeName)))
        }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return .missing }
        do {
            let data = try Data(contentsOf: url)
            return .loaded(try StoreFileReader.read(data, store: storeName, as: T.self))
        } catch let rejection as StoreFileRejection {
            return .failed(StoreFailure(store: storeName, userMessage: rejection.userMessage(for: storeName)))
        } catch {
            return .failed(StoreFailure(store: storeName, userMessage: StoreHealthMessages.loadFailed(storeName)))
        }
    }

    /// Ordinary save path: fail closed. Any existing file must first be a
    /// valid current-version envelope for this store; corrupt, wrong-store,
    /// unsupported-newer, unreadable, and legacy-bare files throw a typed
    /// rejection and stay byte-for-byte untouched. Legacy files remain
    /// read-only until the explicit migration path (with its protected
    /// backup) replaces them. Replacement writes a fresh deterministic
    /// version-1 envelope.
    func save(_ value: T) throws {
        try guardNotLocked()
        try validateReplacableBytes()
        try writeEnvelope(value)
    }

    private func guardNotLocked() throws {
        if mutationLocked() {
            throw StoreFileRejection.migrationInProgress
        }
    }

    private func validateReplacableBytes() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw StoreFileRejection.malformed
        }
        let contents = try StoreFileReader.readWithGeneration(data, store: storeName, as: T.self)
        guard contents.generation == .current else {
            // The legacy original must survive untouched until migration can
            // preserve it with a protected backup and manifest.
            throw StoreFileRejection.legacyNeedsMigration
        }
    }

    /// Writes a fresh version-1 envelope without inspecting existing bytes.
    /// Only first saves and explicit recovery — which already preserved and
    /// verified the original bytes in Damaged Backups — may reach this path;
    /// ordinary saves must go through `save`.
    func writeEnvelope(_ value: T) throws {
        let data = try StoreFileWriter.envelopeData(payload: value, store: storeName)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let temporaryURL = directory.appendingPathComponent("." + url.lastPathComponent + ".tmp-\(UUID().uuidString)")
        try data.write(to: temporaryURL, options: .atomic)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
    }
}

/// Owns the file layout under Application Support/Reflect.
public struct PersistenceController {
    /// Backups of damaged stores live here, inside the private store directory.
    static let damagedBackupsFolderName = "Damaged Backups"
    /// Verified legacy-original backups and migration journals live here, one
    /// folder per migration, inside the private store directory.
    static let migrationBackupsFolderName = StoreMigrationEngine.backupsFolderName

    public let directory: URL
    /// File-operation seam for the explicit migration path only. Production
    /// uses plain FileManager; tests inject precise failures. Ordinary loads
    /// and saves never consult it.
    let migrationFiles: MigrationFileServing

    /// True while an explicit migration or rollback is in progress in this
    /// directory. A manifest that exists but cannot be understood fails
    /// closed: the directory counts as locked.
    static func isStoreMigrationActive(in directory: URL) -> Bool {
        StoreMigrationEngine(directory: directory, files: SystemMigrationFileService()).migrationLockIsActive()
    }

    private var eventsStore: JSONFileStore<[EvidenceEvent]> {
        JSONFileStore(url: directory.appendingPathComponent("events.json"), storeName: .events, mutationLocked: { [directory] in PersistenceController.isStoreMigrationActive(in: directory) })
    }
    private var correctionsStore: JSONFileStore<[AttributionCorrection]> {
        JSONFileStore(url: directory.appendingPathComponent("corrections.json"), storeName: .corrections, mutationLocked: { [directory] in PersistenceController.isStoreMigrationActive(in: directory) })
    }
    private var reportsStore: JSONFileStore<[DailyReport]> {
        JSONFileStore(url: directory.appendingPathComponent("reports.json"), storeName: .reports, mutationLocked: { [directory] in PersistenceController.isStoreMigrationActive(in: directory) })
    }
    private var settingsStore: JSONFileStore<AppSettings> {
        JSONFileStore(url: directory.appendingPathComponent("settings.json"), storeName: .settings, mutationLocked: { [directory] in PersistenceController.isStoreMigrationActive(in: directory) })
    }
    private var manifestsStore: JSONFileStore<[SourceKind: SourceManifest]> {
        JSONFileStore(url: directory.appendingPathComponent("manifests.json"), storeName: .manifests, mutationLocked: { [directory] in PersistenceController.isStoreMigrationActive(in: directory) })
    }
    /// Normalized session/turn records (M2). Read only by the explicit
    /// session import path — never at launch.
    private var sessionsStore: JSONFileStore<[WorkSession]> {
        JSONFileStore(url: directory.appendingPathComponent("sessions.json"), storeName: .sessions, mutationLocked: { [directory] in PersistenceController.isStoreMigrationActive(in: directory) })
    }
    /// Durable conversation records and messages (M3). Read only by the
    /// conversation service — never at launch, and never by AppStore state.
    private var conversationsStore: JSONFileStore<[StoredConversation]> {
        JSONFileStore(url: directory.appendingPathComponent("conversations.json"), storeName: .conversations, mutationLocked: { [directory] in PersistenceController.isStoreMigrationActive(in: directory) })
    }

    public init(directory: URL) {
        self.init(directory: directory, migrationFiles: SystemMigrationFileService())
    }

    init(directory: URL, migrationFiles: MigrationFileServing) {
        self.directory = directory
        self.migrationFiles = migrationFiles
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(AppConstants.appSupportFolderName, isDirectory: true)
    }

    // MARK: Events

    public func saveEvents(_ events: [EvidenceEvent]) throws { try eventsStore.save(events) }
    public func loadEvents() throws -> [EvidenceEvent] { try eventsStore.load() ?? [] }

    // MARK: Corrections (stored independently of events)

    public func saveCorrections(_ corrections: [AttributionCorrection]) throws { try correctionsStore.save(corrections) }
    public func loadCorrections() throws -> [AttributionCorrection] { try correctionsStore.load() ?? [] }

    // MARK: Reports

    public func saveReports(_ reports: [DailyReport]) throws { try reportsStore.save(reports) }
    public func loadReports() throws -> [DailyReport] { try reportsStore.load() ?? [] }

    // MARK: Settings

    public func saveSettings(_ settings: AppSettings) throws { try settingsStore.save(settings) }
    public func loadSettings() throws -> AppSettings { try settingsStore.load() ?? AppSettings.default() }

    // MARK: Manifests

    public func saveManifests(_ manifests: [SourceKind: SourceManifest]) throws { try manifestsStore.save(manifests) }
    public func loadManifests() throws -> [SourceKind: SourceManifest] { try manifestsStore.load() ?? [:] }

    // MARK: Sessions (normalized session/turn records)

    public func saveSessions(_ sessions: [WorkSession]) throws { try sessionsStore.save(sessions) }
    public func loadSessions() throws -> [WorkSession] { try sessionsStore.load() ?? [] }

    // MARK: Conversations (durable conversation records and messages)

    public func saveConversations(_ conversations: [StoredConversation]) throws { try conversationsStore.save(conversations) }
    public func loadConversations() throws -> [StoredConversation] { try conversationsStore.load() ?? [] }

    // MARK: Typed store health

    public func loadEventsHealth() -> StoreLoad<[EvidenceEvent]> { eventsStore.loadHealth() }
    public func loadCorrectionsHealth() -> StoreLoad<[AttributionCorrection]> { correctionsStore.loadHealth() }
    public func loadReportsHealth() -> StoreLoad<[DailyReport]> { reportsStore.loadHealth() }
    public func loadSettingsHealth() -> StoreLoad<AppSettings> { settingsStore.loadHealth() }
    public func loadManifestsHealth() -> StoreLoad<[SourceKind: SourceManifest]> { manifestsStore.loadHealth() }
    public func loadSessionsHealth() -> StoreLoad<[WorkSession]> { sessionsStore.loadHealth() }
    public func loadConversationsHealth() -> StoreLoad<[StoredConversation]> { conversationsStore.loadHealth() }

    /// Explicit, user-initiated recovery for one damaged store. The original
    /// bytes are copied into `Damaged Backups` inside this private store
    /// directory and verified byte-for-byte before any replacement is
    /// installed. If the backup or the replacement fails, the outcome is
    /// `.failed`, the original file is untouched, and recovery stays possible.
    public func recoverStore(_ store: StoreName) -> StoreRecoveryOutcome {
        if PersistenceController.isStoreMigrationActive(in: directory) {
            // While a migration or rollback is in progress it is the only
            // permitted mutation; recovery would race a mixed generation.
            return .failed(message: StoreHealthMessages.recoveryBlockedByMigration(store))
        }
        let fileManager = FileManager.default
        let fileURL = directory.appendingPathComponent(store.fileName)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            // Nothing to preserve: absence is a valid state, so installing a
            // fresh default store is safe.
            do {
                try installDefaultReplacement(for: store)
                return .recovered
            } catch {
                return .failed(message: StoreHealthMessages.recoveryInstallFailed(store))
            }
        }

        let original: Data
        do {
            original = try Data(contentsOf: fileURL)
        } catch {
            return .failed(message: StoreHealthMessages.recoveryReadFailed(store))
        }

        do {
            let backupsDirectory = directory.appendingPathComponent(Self.damagedBackupsFolderName, isDirectory: true)
            try fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
            let backupURL = backupsDirectory.appendingPathComponent("\(store.rawValue)-damaged-\(UUID().uuidString).json")
            try original.write(to: backupURL, options: .atomic)
            let verified = try Data(contentsOf: backupURL)
            guard verified == original else {
                try? fileManager.removeItem(at: backupURL)
                return .failed(message: StoreHealthMessages.recoveryVerifyFailed(store))
            }
        } catch {
            return .failed(message: StoreHealthMessages.recoveryBackupFailed(store))
        }

        do {
            try installDefaultReplacement(for: store)
        } catch {
            return .failed(message: StoreHealthMessages.recoveryInstallFailed(store))
        }
        return .recovered
    }

    private func installDefaultReplacement(for store: StoreName) throws {
        // Recovery installs fresh envelopes without the ordinary fail-closed
        // byte inspection: the damaged bytes were already backed up and
        // verified above, and the damaged file must be replaceable here.
        switch store {
        case .events: try eventsStore.writeEnvelope([])
        case .corrections: try correctionsStore.writeEnvelope([])
        case .reports: try reportsStore.writeEnvelope([])
        case .settings: try settingsStore.writeEnvelope(AppSettings.default())
        case .manifests: try manifestsStore.writeEnvelope([:])
        case .sessions: try sessionsStore.writeEnvelope([])
        case .conversations: try conversationsStore.writeEnvelope([])
        }
    }

    // MARK: Explicit legacy-store migration

    /// Explicitly upgrades every legacy bare store file (schema version 0) in
    /// this directory to the current version-1 envelope. Never runs
    /// implicitly: calling this method is the only way migration starts.
    ///
    /// The migration is durable and safe by construction: every present store
    /// is classified before any byte changes (corrupt, wrong-store, malformed,
    /// and newer files abort untouched), the exact original bytes of every
    /// legacy store are preserved in a verified backup under
    /// `Migration Backups/<migration UUID>/` and kept indefinitely, all
    /// version-1 envelopes are staged and validated before any replacement,
    /// and every phase is journaled to a private manifest before the matching
    /// mutation. If a store file's bytes match neither the recorded original
    /// nor the expected migrated bytes, the migration stops and preserves
    /// everything — unknown externally changed bytes are never overwritten.
    /// Calling this again while a migration is in progress resumes it; calling
    /// it again after completion is an idempotent no-op that creates no new
    /// backups.
    ///
    /// While the migration is in progress, ordinary reads fail typed and
    /// ordinary saves are blocked, so no mixed generation can be consumed or
    /// written; finishing, retrying, or rolling back explicitly lifts the
    /// lock.
    @discardableResult
    public func migrateLegacyStores() -> StoreMigrationOutcome {
        StoreMigrationEngine(directory: directory, files: migrationFiles).migrate()
    }

    /// Explicitly restores every participant of a recorded migration to its
    /// exact legacy original bytes from the verified backups. Preflight
    /// requires every store file to match the recorded original or target
    /// hash and every backup to verify against the original hash; a partially
    /// interrupted rollback retries safely from the journal. The backups and
    /// manifest are kept with a `rolled-back` status, and nothing is ever
    /// rolled back or cleaned up automatically.
    @discardableResult
    public func rollbackLegacyStoreMigration() -> StoreMigrationOutcome {
        StoreMigrationEngine(directory: directory, files: migrationFiles).rollback()
    }
}
