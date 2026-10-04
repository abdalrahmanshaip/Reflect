import Foundation

/// Identifies one persisted JSON store under Reflect's private data folder.
/// Codable so typed metadata (for example, a context envelope's missing-store
/// list) can be persisted; encoding uses the stable raw value and changes no
/// existing store payload shape.
public enum StoreName: String, CaseIterable, Codable, Hashable {
    case events
    case corrections
    case reports
    case settings
    case manifests
    case sessions
    case conversations

    public var displayName: String {
        switch self {
        case .events: return "Events"
        case .corrections: return "Corrections"
        case .reports: return "Reports"
        case .settings: return "Settings"
        case .manifests: return "Import state"
        case .sessions: return "Sessions"
        case .conversations: return "Conversations"
        }
    }

    var fileName: String { rawValue + ".json" }
}

/// A store read or decode failure. Carries only the affected store and a safe
/// English user message — never payload bytes, transcript content, or paths.
public struct StoreFailure: Error, Equatable {
    public let store: StoreName
    public let userMessage: String

    public init(store: StoreName, userMessage: String) {
        self.store = store
        self.userMessage = userMessage
    }
}

/// Typed outcome of loading one store. `missing` is the valid first-run state;
/// `failed` is a damaged store that must never be treated as empty or replaced
/// by an ordinary save.
public enum StoreLoad<Value> {
    case missing
    case loaded(Value)
    case failed(StoreFailure)
}

extension StoreLoad: Equatable where Value: Equatable {}

/// Explicit, user-initiated recovery results.
public enum StoreRecoveryOutcome: Equatable {
    case recovered
    case failed(message: String)
}

/// Explicit, user-initiated legacy-store migration and rollback results.
/// Messages are safe English: they name stores only — never payload bytes,
/// transcript content, or private paths.
public enum StoreMigrationOutcome: Equatable {
    /// Every legacy store present at preflight was upgraded to the current
    /// envelope and the migration is journaled complete.
    case migrated(migrationID: UUID, stores: [StoreName])
    /// No legacy store was present (all current or missing), so there was
    /// nothing to do and no new backup was created.
    case alreadyCurrent
    /// Every participant store was restored to its exact legacy original
    /// bytes from the verified backups.
    case rolledBack(migrationID: UUID, stores: [StoreName])
    /// No migration manifest exists to roll back.
    case nothingToRollBack
    /// The operation stopped before or during mutation; every byte on disk is
    /// preserved and the operation can be retried explicitly.
    case failed(message: String)
}

/// Safe English messages for store health surfaces. They name the affected
/// store only — never payload bytes, transcript content, or private paths.
enum StoreHealthMessages {
    static func loadFailed(_ store: StoreName) -> String {
        "The \(store.displayName) store could not be read or decoded. Reflect left the file untouched and will not save over it until you recover it from Settings."
    }

    static func saveBlocked(_ store: StoreName) -> String {
        "Saving \(store.displayName.lowercased()) is blocked until the damaged store is recovered. Open Settings > Local data to recover it."
    }

    /// Safe message for an ordinary save that failed. It names the affected
    /// store and states that the attempted change was not saved or published.
    /// It never includes the underlying OS error text, file names, temp
    /// identifiers, private paths, or payload — those details stay out of the
    /// user-facing error surface by design.
    static func saveFailed(_ store: StoreName) -> String {
        switch store {
        case .reports:
            return "Saving your reflection failed, so it was not saved. Your text stays in the composer — try saving again."
        default:
            return "Saving \(store.displayName.lowercased()) failed, so the attempted change was not saved or published. Try again."
        }
    }

    /// Safe message for a file that carries another store's identity. It names
    /// the affected store only — never payload bytes or private paths.
    static func wrongStoreContent(_ store: StoreName) -> String {
        "The \(store.displayName) file holds data for a different store. Reflect left the file untouched and will not save over it until you recover it from Settings."
    }

    /// Safe message for a store file written by a newer schema version. It
    /// names the affected store only — never payload bytes or private paths.
    static func unsupportedSchemaVersion(_ store: StoreName) -> String {
        "The \(store.displayName) file was written by a newer version of Reflect. Reflect left the file untouched and will not save over it."
    }

    /// Safe message for a store file whose schema version cannot be used. It
    /// names the affected store only — never payload bytes or private paths.
    static func invalidSchemaVersion(_ store: StoreName) -> String {
        "The \(store.displayName) file has an unreadable schema version. Reflect left the file untouched and will not save over it until you recover it from Settings."
    }

    /// Safe message for a store file that still uses the pre-envelope format.
    /// It states that the store was read safely and left untouched, and that
    /// saving pauses until the explicit migration (with a protected backup)
    /// exists — it never promises a control that is not there yet, and it
    /// names the affected store only — never payload bytes or private paths.
    static func legacyNeedsMigration(_ store: StoreName) -> String {
        "The \(store.displayName) store still uses the older storage format. Reflect read it safely and left the file untouched; saving for this store pauses until the store is migrated to the current format with a protected backup."
    }

    static func recoveryReadFailed(_ store: StoreName) -> String {
        "Recovery stopped before changing anything: the damaged \(store.displayName) file could not be read."
    }

    static func recoveryBackupFailed(_ store: StoreName) -> String {
        "Recovery stopped before changing anything: a backup copy of the damaged \(store.displayName) file could not be created. The original file is untouched."
    }

    static func recoveryVerifyFailed(_ store: StoreName) -> String {
        "Recovery stopped before changing anything: the backup copy could not be verified. The original \(store.displayName) file is untouched."
    }

    static func recoveryInstallFailed(_ store: StoreName) -> String {
        "Recovery preserved a backup but could not install a fresh \(store.displayName) store. The original file is untouched and remains recoverable."
    }

    static func recoveryBlockedByMigration(_ store: StoreName) -> String {
        "Recovery for the \(store.displayName) store is paused because a storage format migration is in progress. Finish or roll back the migration first."
    }

    /// Safe message for reads and ordinary saves paused by an in-progress
    /// store migration or rollback. It names the affected store only.
    static func migrationInProgress(_ store: StoreName) -> String {
        "A storage format migration is in progress, so reading and saving \(store.displayName.lowercased()) is paused. Finish, retry, or roll back the migration from Settings to continue."
    }
}
