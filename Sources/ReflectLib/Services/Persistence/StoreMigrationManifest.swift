import Foundation
import CryptoKit

/// The on-disk journal for one explicit legacy-store migration. The manifest
/// records only structural facts — migration identity, progress status, store
/// identity, byte hashes, and backup file names relative to the migration
/// folder. It never records payload contents, absolute paths, transcript
/// strings, or credentials. It is written as deterministic sorted JSON with
/// atomic writes, and every phase is journaled before the mutation it
/// describes.
struct StoreMigrationManifest: Codable, Equatable {
    static let formatVersion = 1
    static let fileName = "manifest.json"

    var formatVersion: Int
    var migrationID: String
    var status: StoreMigrationProgress
    /// Participants in stable store-raw-value order.
    var stores: [StoreMigrationRecord]

    init(migrationID: UUID, status: StoreMigrationProgress, stores: [StoreMigrationRecord]) {
        self.formatVersion = Self.formatVersion
        self.migrationID = migrationID.uuidString
        self.status = status
        self.stores = stores
    }
}

/// Journal phases of a migration or rollback. The in-progress phases
/// (`backingUp`, `applying`, `rollingBack`) hold the migration lock: reads and
/// ordinary saves pause while any of them is recorded. `complete` and
/// `rolledBack` are terminal and lift the lock.
enum StoreMigrationProgress: String, Codable, Equatable {
    case backingUp
    case applying
    case complete
    case rollingBack
    case rolledBack

    var isInProgress: Bool {
        switch self {
        case .backingUp, .applying, .rollingBack: return true
        case .complete, .rolledBack: return false
        }
    }
}

/// Per-store journal entry. The boolean flags are journaled before the
/// mutation they describe, so an interruption is always detectable; on any
/// retry the actual on-disk bytes (checked against the recorded hashes) are
/// the source of truth, never the flags alone.
struct StoreMigrationRecord: Codable, Equatable {
    /// Stable store identity (`StoreName` raw value).
    var store: String
    /// SHA-256 hex digest of the exact legacy original bytes.
    var originalHash: String
    /// Backup file name relative to the migration folder (e.g. `events.json`).
    var backupPath: String
    /// SHA-256 hex digest of the expected migrated version-1 envelope bytes.
    var targetHash: String
    /// Journaled after the backup was written and verified byte-for-byte.
    var backupVerified: Bool
    /// Journaled before replacing the store file with the staged envelope.
    var replaced: Bool
    /// Journaled before restoring the legacy original during rollback.
    var restored: Bool
}

/// Deterministic SHA-256 hex digests for byte comparisons. Digests never
/// contain payload content: they are one-way.
enum StoreFileHashing {
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// File-operation seam for the migration engine. The production
/// implementation is plain FileManager; tests may inject failures at precise
/// operations instead of relying on root-sensitive permission games. Only the
/// migration path consults this seam; ordinary loads and saves are untouched.
protocol MigrationFileServing {
    func data(at url: URL) throws -> Data
    func exists(_ url: URL) -> Bool
    func writeAtomic(_ data: Data, to url: URL) throws
    func replaceItem(at target: URL, withItemAt staged: URL) throws
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws
    func contentsOfDirectory(at url: URL) throws -> [URL]
}

/// Production implementation of the migration file seam.
struct SystemMigrationFileService: MigrationFileServing {
    func data(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func writeAtomic(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    func replaceItem(at target: URL, withItemAt staged: URL) throws {
        _ = try FileManager.default.replaceItemAt(target, withItemAt: staged)
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }
}

/// Typed errors the migration engine reports. They are structural facts only;
/// user-facing text comes from the safe message mapping, never from OS error
/// text.
enum StoreMigrationError: Error, Equatable {
    /// A present store file is corrupt, wrong-store, malformed, or newer than
    /// the supported schema — preflight aborts before any mutation. The safe
    /// rejection message is carried through from the typed reader.
    case storeRejected(message: String)
    /// A store file's bytes match neither the recorded original legacy bytes
    /// nor the expected migrated envelope bytes: an outside change happened.
    case externalByteChange(store: StoreName)
    /// A backup is missing or no longer matches the original hash it must
    /// preserve.
    case backupMismatch(store: StoreName)
    /// A recorded backup or staged file's hash disagrees with the manifest.
    case manifestConflict(store: StoreName)
    /// Prepared version-1 envelope bytes failed decode round-trip validation
    /// before any replacement; nothing was changed.
    case stagedValidationFailed(store: StoreName)
    /// A manifest exists but cannot be decoded or is not understood.
    case manifestUnreadable
    /// More than one non-terminal manifest was found; refusing to guess.
    case conflictingManifests
    /// Migration cannot start because a rollback is in progress.
    case rollbackInProgress
    /// An injected or underlying file operation failed mid-phase. Everything
    /// already written stays; retry resumes from the journal.
    case interrupted
}

extension StoreMigrationError {
    /// Safe English text for the migration outcome surface. It names stores
    /// only — never payload bytes, transcript content, or private paths.
    var safeMessage: String {
        switch self {
        case .storeRejected(let message):
            return message
        case .externalByteChange(let store):
            return "Migration stopped: the \(store.displayName) file changed outside this migration. Reflect preserved every byte and will not overwrite it; review the files, then retry explicitly."
        case .backupMismatch(let store):
            return "Migration stopped: the protected backup of the \(store.displayName) store no longer matches its original. Reflect preserved every byte and will not continue without a verified backup."
        case .manifestConflict(let store):
            return "Migration stopped: the migration journal for the \(store.displayName) store does not match the files on disk. Reflect preserved every byte."
        case .stagedValidationFailed(let store):
            return "Migration stopped before changing anything: the prepared current-format copy of the \(store.displayName) store failed validation. Reflect preserved every byte."
        case .manifestUnreadable:
            return "Migration stopped: the migration journal could not be read. Reflect preserved every byte and will not overwrite anything until the journal is understood."
        case .conflictingManifests:
            return "Migration stopped: more than one unfinished migration journal was found. Reflect preserved every byte and will not guess which one to continue."
        case .rollbackInProgress:
            return "A rollback of a previous migration is still in progress. Finish or retry the rollback before starting a migration."
        case .interrupted:
            return "Migration stopped mid-way and kept every byte written so far. Retry the migration to resume safely, or roll it back to restore the previous format."
        }
    }
}
