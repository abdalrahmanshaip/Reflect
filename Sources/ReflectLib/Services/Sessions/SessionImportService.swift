import Foundation

/// Per-import scan facts surfaced to the caller. Payload text never enters
/// an outcome.
public struct SessionScanReport: Equatable {
    public let recordLineCount: Int
    public let malformedLineCount: Int
    public let skippedRecordCount: Int
}

/// The typed outcome of one explicit session-file import. Messages are safe
/// English: they never include payload bytes, transcript content, or paths.
public enum SessionImportOutcome: Equatable {
    case imported(
        sessionStableID: String,
        sourceSessionID: String?,
        addedSessions: Int,
        addedTurns: Int,
        revisedTurns: Int,
        scan: SessionScanReport
    )
    /// The file was read but held no records this parser retains as a
    /// session, so nothing was written.
    case noSupportedRecords(scan: SessionScanReport)
    /// The import stopped before writing: unreadable file, damaged store, or
    /// blocked save. The store file stays byte-for-byte untouched.
    case failed(message: String)
}

/// Explicit, opt-in import of one Codex JSONL file into the versioned
/// `sessions` store. It is the only reader of its source file, the source is
/// never written, and nothing here runs at launch or calls an AI service.
///
/// Fail-closed behavior: when the sessions store is damaged, unreadable, or
/// locked by an in-progress migration, the import reports the typed failure
/// and never treats the store as empty; when the save fails, nothing is
/// published as imported.
struct SessionImportService {
    let persistence: PersistenceController
    let importer: CodexSessionImporter

    init(persistence: PersistenceController, importer: CodexSessionImporter = CodexSessionImporter()) {
        self.persistence = persistence
        self.importer = importer
    }

    func importCodexSessionFile(at fileURL: URL, now: Date = Date()) -> SessionImportOutcome {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            return .failed(message: "The session file could not be read. Nothing was imported.")
        }

        let normalization = importer.normalize(data: data, filePath: fileURL.path, now: now)
        let scan = SessionScanReport(
            recordLineCount: normalization.scan.recordLineCount,
            malformedLineCount: normalization.scan.malformedLineCount,
            skippedRecordCount: normalization.scan.skippedRecordCount
        )
        guard let normalized = normalization.session else {
            return .noSupportedRecords(scan: scan)
        }

        let existing: [WorkSession]
        switch persistence.loadSessionsHealth() {
        case .missing:
            existing = []
        case .loaded(let sessions):
            existing = sessions
        case .failed(let failure):
            // A damaged or locked store is never treated as empty: the import
            // stops before writing so no bytes can be destroyed.
            return .failed(message: failure.userMessage)
        }

        let session = Self.makeSession(from: normalized, now: now)
        let (merged, delta) = SessionMerger.merge(existing: existing, incoming: session, importedAt: now)
        guard delta.changed else {
            return .imported(
                sessionStableID: session.id,
                sourceSessionID: session.sourceSessionID,
                addedSessions: 0,
                addedTurns: 0,
                revisedTurns: 0,
                scan: scan
            )
        }

        do {
            try persistence.saveSessions(merged)
        } catch {
            return .failed(message: StoreHealthMessages.saveFailed(.sessions))
        }

        return .imported(
            sessionStableID: session.id,
            sourceSessionID: session.sourceSessionID,
            addedSessions: delta.addedSessions,
            addedTurns: delta.addedTurns,
            revisedTurns: delta.revisedTurns,
            scan: scan
        )
    }

    /// Builds the persisted session record from a normalized file result.
    /// Turn order matches source record order, so sequences are the ordered
    /// indexes.
    static func makeSession(from normalized: CodexSessionImporter.NormalizedSession, now: Date) -> WorkSession {
        var turns = normalized.turns
        for index in turns.indices {
            turns[index].sequence = index
        }
        return WorkSession(
            id: normalized.stableID,
            sourceKind: .codex,
            sourceSessionID: normalized.sourceSessionID,
            title: normalized.title,
            project: normalized.project,
            importRevision: 1,
            firstImportedAt: now,
            lastImportedAt: now,
            startedAt: normalized.startedAt,
            startedAtApproximate: normalized.startedAtApproximate,
            lastActivityAt: normalized.coverage.lastRecordedAt,
            turns: turns,
            coverage: normalized.coverage
        )
    }
}
