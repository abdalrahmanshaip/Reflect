import Foundation

/// Safe, keyed outcome of one import run for a single source. Results are
/// stored per source, so one completion never erases another source's result.
/// The message carries only the source name, record counts, and honest state —
/// never imported payload text or private paths.
public struct ImportSourceResult: Equatable {
    public enum Status: Equatable {
        /// Imported records are durable: events are saved and published, and
        /// the source manifest advanced.
        case imported
        /// The source ran and returned an honest note (for example "not
        /// detected") without a persistence failure.
        case importerNote
        /// The events write failed: nothing was published, and the found
        /// records remain retryable through the import action.
        case retryableSaveFailure
        /// Events are durable and published, but the manifest write failed:
        /// coverage on the source card may be stale until a later import.
        case manifestSaveFailed
    }

    public let kind: SourceKind
    public let status: Status
    public let addedCount: Int
    public let filesScanned: Int
    public let message: String

    public init(kind: SourceKind, status: Status, addedCount: Int, filesScanned: Int, message: String) {
        self.kind = kind
        self.status = status
        self.addedCount = addedCount
        self.filesScanned = filesScanned
        self.message = message
    }
}

extension ImportSourceResult {
    /// Outcome when the events write failed: nothing was published, and the
    /// found records stay retryable through the import action.
    public static func eventWriteFailed(kind: SourceKind, addedCount: Int) -> ImportSourceResult {
        ImportSourceResult(
            kind: kind,
            status: .retryableSaveFailure,
            addedCount: addedCount,
            filesScanned: 0,
            message: "\(kind.displayName): \(addedCount) new record(s) found but not saved — Reflect could not write to disk. Try importing again."
        )
    }

    /// Outcome when the import ran to completion. `manifestAdvanced` false
    /// means the records are saved and shown, but coverage was not recorded —
    /// the message must never claim the manifest advanced.
    public static func completed(
        kind: SourceKind,
        addedCount: Int,
        filesScanned: Int,
        note: String?,
        manifestAdvanced: Bool
    ) -> ImportSourceResult {
        var message: String
        if let note {
            message = safeNoteMessage(kind: kind, note: note)
        } else {
            message = "\(kind.displayName): \(addedCount) new record(s) added, \(filesScanned) file(s) scanned."
        }
        var status: Status
        if manifestAdvanced {
            status = note == nil ? .imported : .importerNote
        } else {
            status = .manifestSaveFailed
            message += " Imported records are saved and shown, but the coverage manifest could not be updated; counts shown here may be stale."
        }
        return ImportSourceResult(
            kind: kind,
            status: status,
            addedCount: addedCount,
            filesScanned: filesScanned,
            message: message
        )
    }

    /// Importer notes are untrusted display input. Keep only known, app-authored
    /// status copy so adapter errors or future notes cannot expose local paths
    /// or imported text in the per-source result.
    private static func safeNoteMessage(kind: SourceKind, note: String) -> String {
        let normalized = note.lowercased()
        let safeCopy: String
        if normalized.contains("not detected") {
            safeCopy = "Source not detected at the expected location under the home directory."
        } else if normalized.contains("format not yet verified") {
            safeCopy = "Detected; format not yet verified. Import is intentionally unavailable for this structured store."
        } else if normalized.contains("no repository selected") {
            safeCopy = "No repository selected. Choose one in the Sources tab."
        } else if normalized.contains("git import failed") {
            safeCopy = "Git import failed. Check the selected repository and try again."
        } else if normalized.contains("source is disabled") {
            safeCopy = "Source is disabled in Settings."
        } else {
            safeCopy = "Import completed with a source note."
        }
        return "\(kind.displayName): \(safeCopy)"
    }
}
