import Foundation

/// The durable, explicit migration engine that upgrades legacy bare store
/// files (schema version 0) to the current version-1 envelope.
///
/// Safety rules implemented here:
/// - Preflight classifies every present store before any byte changes;
///   corrupt, wrong-store, malformed, or newer files abort with nothing
///   touched, and errors are never treated as empty stores.
/// - Original legacy bytes are preserved byte-for-byte in
///   `Migration Backups/<migration UUID>/<store>.json`, verified before any
///   replacement, and kept indefinitely.
/// - A private manifest journals phases before each mutation so an
///   interruption is always detectable and a retry resumes safely by
///   verifying actual on-disk bytes against recorded hashes.
/// - Rollback restores the exact legacy originals from the verified backups,
///   is itself resumable, and keeps the backups and manifest.
/// - No automatic rollback, cleanup, or force-overwrite exists anywhere.
struct StoreMigrationEngine {
    static let backupsFolderName = "Migration Backups"
    static let stagedPrefix = "staged-"

    let directory: URL
    let files: MigrationFileServing

    var backupsRoot: URL {
        directory.appendingPathComponent(Self.backupsFolderName, isDirectory: true)
    }

    // MARK: Journal discovery

    struct Journal {
        let folder: URL
        let manifestURL: URL
        var manifest: StoreMigrationManifest
    }

    /// Every journaled migration folder under `Migration Backups`, ordered by
    /// folder name. A folder counts only when its manifest file is present.
    private func findJournals() throws -> [Journal] {
        guard files.exists(backupsRoot) else { return [] }
        let folders: [URL]
        do {
            folders = try files.contentsOfDirectory(at: backupsRoot)
        } catch {
            throw StoreMigrationError.manifestUnreadable
        }
        var journals: [Journal] = []
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let manifestURL = folder.appendingPathComponent(StoreMigrationManifest.fileName)
            guard files.exists(manifestURL) else { continue }
            guard let data = try? files.data(at: manifestURL),
                  let manifest = try? JSONDecoder().decode(StoreMigrationManifest.self, from: data),
                  manifest.formatVersion == StoreMigrationManifest.formatVersion else {
                throw StoreMigrationError.manifestUnreadable
            }
            journals.append(Journal(folder: folder, manifestURL: manifestURL, manifest: manifest))
        }
        return journals
    }

    /// Whether the store directory is locked by an in-progress migration or
    /// rollback. A manifest that exists but cannot be understood fails closed:
    /// the directory counts as locked so a mixed generation can never be
    /// consumed or overwritten.
    func migrationLockIsActive() -> Bool {
        guard files.exists(backupsRoot) else { return false }
        do {
            for journal in try findJournals() where journal.manifest.status.isInProgress {
                return true
            }
            return false
        } catch {
            return true
        }
    }

    // MARK: Migration

    /// Plans are preflight classifications; `nil` means the store is missing
    /// or already current and needs no migration.
    private struct MigrationPlan {
        let store: StoreName
        let originalBytes: Data
        let targetBytes: Data
    }

    func migrate() -> StoreMigrationOutcome {
        do {
            let journals = try findJournals()
            if journals.contains(where: { $0.manifest.status == .rollingBack }) {
                return .failed(message:StoreMigrationError.rollbackInProgress.safeMessage)
            }
            let active = journals.filter { $0.manifest.status.isInProgress }
            if active.count > 1 {
                return .failed(message:StoreMigrationError.conflictingManifests.safeMessage)
            }
            if let journal = active.first {
                return try apply(journal: journal)
            }
            return try startAndApply()
        } catch let error as StoreMigrationError {
            return .failed(message:error.safeMessage)
        } catch {
            return .failed(message:StoreMigrationError.interrupted.safeMessage)
        }
    }

    /// Fresh start: preflight every store, and only if at least one legacy
    /// store exists create the journal folder, stage and verify the version-1
    /// envelopes, journal them, verify backups, and replace — in that order.
    /// Staging happens before the manifest exists, so a manifest always
    /// describes target bytes that are already on disk; a crash before the
    /// manifest leaves an inert folder that no journal or lock recognizes.
    private func startAndApply() throws -> StoreMigrationOutcome {
        var plans: [MigrationPlan] = []
        for store in StoreName.allCases {
            if let plan = try classifyStore(store) {
                plans.append(plan)
            }
        }
        guard !plans.isEmpty else { return .alreadyCurrent }

        let migrationID = UUID()
        let folder = backupsRoot.appendingPathComponent(migrationID.uuidString, isDirectory: true)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)

        let records = plans.map { plan in
            StoreMigrationRecord(
                store: plan.store.rawValue,
                originalHash: StoreFileHashing.sha256Hex(plan.originalBytes),
                backupPath: plan.store.fileName,
                targetHash: StoreFileHashing.sha256Hex(plan.targetBytes),
                backupVerified: false,
                replaced: false,
                restored: false
            )
        }

        // Stage every target envelope first and verify each staged file by
        // reading it back. Equal payloads may encode with different element
        // order across separate decodes (unordered collections), so these
        // exact staged bytes — never a re-encode — are the migration's target
        // from here on.
        for plan in plans {
            let stagedURL = folder.appendingPathComponent(Self.stagedPrefix + plan.store.fileName)
            try files.writeAtomic(plan.targetBytes, to: stagedURL)
            guard StoreFileHashing.sha256Hex(try readOrInterrupt(stagedURL)) == StoreFileHashing.sha256Hex(plan.targetBytes) else {
                throw StoreMigrationError.interrupted
            }
        }

        let manifest = StoreMigrationManifest(migrationID: migrationID, status: .backingUp, stores: records)
        let manifestURL = folder.appendingPathComponent(StoreMigrationManifest.fileName)
        try writeManifest(manifest, to: manifestURL)

        let journal = Journal(folder: folder, manifestURL: manifestURL, manifest: manifest)
        return try apply(journal: journal)
    }

    /// The apply phase, shared by fresh starts and retries. Every store file
    /// must hash to either the recorded original legacy bytes or the expected
    /// migrated envelope bytes; anything else stops safely without overwrite.
    private func apply(journal inputJournal: Journal) throws -> StoreMigrationOutcome {
        var journal = inputJournal
        let migrationID = try journalID(journal)

        // Byte-state of every participant, re-derived from disk on every call.
        var states: [String: ByteState] = [:]
        for record in journal.manifest.stores {
            guard record.replaced == false || record.backupVerified else {
                throw StoreMigrationError.manifestConflict(store: StoreName(rawValue: record.store) ?? .events)
            }
            states[record.store] = try classifyBytes(for: record)
        }

        // Phase 1: every participant has a verified backup before any store
        // file is replaced.
        for index in journal.manifest.stores.indices {
            var record = journal.manifest.stores[index]
            let backupURL = journal.folder.appendingPathComponent(record.backupPath)
            if record.backupVerified {
                guard files.exists(backupURL),
                      StoreFileHashing.sha256Hex(try readOrInterrupt(backupURL)) == record.originalHash else {
                    throw StoreMigrationError.backupMismatch(store: storeNamed(record.store))
                }
            } else {
                guard states[record.store] == .original else {
                    throw StoreMigrationError.manifestConflict(store: storeNamed(record.store))
                }
                let originalBytes = try readOrInterrupt(storeURL(for: record))
                try files.writeAtomic(originalBytes, to: backupURL)
                guard StoreFileHashing.sha256Hex(try readOrInterrupt(backupURL)) == record.originalHash else {
                    throw StoreMigrationError.backupMismatch(store: storeNamed(record.store))
                }
                record.backupVerified = true
                journal.manifest.stores[index] = record
                try writeManifest(journal.manifest, to: journal.manifestURL)
            }
        }

        // Phase 2: stage and validate every version-1 envelope before any
        // original is replaced. The target bytes are pinned from the
        // authenticated legacy original bytes, so a resumed run always
        // verifies each store against exactly the bytes it will write — even
        // though payloads holding unordered collections (a settings Set, for
        // example) may legitimately encode in different element order across
        // separate decodes. The journal is updated to the pinned hash before
        // anything is replaced.
        for index in journal.manifest.stores.indices {
            var record = journal.manifest.stores[index]
            guard let state = states[record.store] else {
                throw StoreMigrationError.manifestConflict(store: storeNamed(record.store))
            }
            guard state == .original else { continue }
            let currentBytes = try readOrInterrupt(storeURL(for: record))
            let staged = try stagedBytes(for: storeNamed(record.store), from: currentBytes, isOriginal: true)
            let targetHash = StoreFileHashing.sha256Hex(staged)
            let stagedURL = journal.folder.appendingPathComponent(Self.stagedPrefix + record.backupPath)
            let stagedAlreadyCorrect: Bool
            if files.exists(stagedURL) {
                stagedAlreadyCorrect = StoreFileHashing.sha256Hex(try readOrInterrupt(stagedURL)) == targetHash
            } else {
                stagedAlreadyCorrect = false
            }
            if !stagedAlreadyCorrect {
                try files.writeAtomic(staged, to: stagedURL)
                guard StoreFileHashing.sha256Hex(try readOrInterrupt(stagedURL)) == targetHash else {
                    throw StoreMigrationError.interrupted
                }
            }
            if record.targetHash != targetHash {
                record.targetHash = targetHash
                journal.manifest.stores[index] = record
                try writeManifest(journal.manifest, to: journal.manifestURL)
            }
        }

        // Phase 3: journal the apply phase, then replace atomically one by
        // one, journaling each replacement before it happens.
        if journal.manifest.status != .applying {
            journal.manifest.status = .applying
            try writeManifest(journal.manifest, to: journal.manifestURL)
        }
        for index in journal.manifest.stores.indices {
            var record = journal.manifest.stores[index]
            guard let state = states[record.store] else {
                throw StoreMigrationError.manifestConflict(store: storeNamed(record.store))
            }
            guard state == .original else { continue }
            record.replaced = true
            journal.manifest.stores[index] = record
            try writeManifest(journal.manifest, to: journal.manifestURL)

            let storeURL = storeURL(for: record)
            let stagedURL = journal.folder.appendingPathComponent(Self.stagedPrefix + record.backupPath)
            let stagedBytes = try readOrInterrupt(stagedURL)
            let temporaryURL = storeURL.deletingLastPathComponent()
                .appendingPathComponent("." + storeURL.lastPathComponent + ".tmp-\(UUID().uuidString)")
            try files.writeAtomic(stagedBytes, to: temporaryURL)
            try files.replaceItem(at: storeURL, withItemAt: temporaryURL)
            guard StoreFileHashing.sha256Hex(try readOrInterrupt(storeURL)) == record.targetHash else {
                throw StoreMigrationError.interrupted
            }
            states[record.store] = .target
        }

        journal.manifest.status = .complete
        try writeManifest(journal.manifest, to: journal.manifestURL)
        return .migrated(
            migrationID: migrationID,
            stores: journal.manifest.stores.compactMap { StoreName(rawValue: $0.store) }
        )
    }

    // MARK: Rollback

    func rollback() -> StoreMigrationOutcome {
        do {
            let journals = try findJournals()
            let candidates = journals.filter { $0.manifest.status != .rolledBack }
            guard !candidates.isEmpty else { return .nothingToRollBack }
            guard candidates.count == 1 else {
                return .failed(message:StoreMigrationError.conflictingManifests.safeMessage)
            }
            var journal = candidates[0]
            let migrationID = try journalID(journal)

            // Preflight every participant: store bytes must be the recorded
            // original or the migrated target, and every verified backup must
            // still match the original hash it preserves.
            var states: [String: ByteState] = [:]
            for record in journal.manifest.stores {
                guard record.replaced == false || record.backupVerified else {
                    throw StoreMigrationError.manifestConflict(store: storeNamed(record.store))
                }
                let state = try classifyBytes(for: record)
                if record.backupVerified {
                    let backupURL = journal.folder.appendingPathComponent(record.backupPath)
                    guard files.exists(backupURL),
                          StoreFileHashing.sha256Hex(try readOrInterrupt(backupURL)) == record.originalHash else {
                        throw StoreMigrationError.backupMismatch(store: storeNamed(record.store))
                    }
                } else {
                    guard state == .original else {
                        throw StoreMigrationError.manifestConflict(store: storeNamed(record.store))
                    }
                }
                states[record.store] = state
            }

            // Journal the rollback phase before mutating anything.
            if journal.manifest.status != .rollingBack {
                journal.manifest.status = .rollingBack
                try writeManifest(journal.manifest, to: journal.manifestURL)
            }

            for index in journal.manifest.stores.indices {
                var record = journal.manifest.stores[index]
                guard let state = states[record.store] else {
                    throw StoreMigrationError.manifestConflict(store: storeNamed(record.store))
                }
                guard state == .target else {
                    if !record.restored {
                        record.restored = true
                        journal.manifest.stores[index] = record
                        try writeManifest(journal.manifest, to: journal.manifestURL)
                    }
                    continue
                }
                record.restored = true
                journal.manifest.stores[index] = record
                try writeManifest(journal.manifest, to: journal.manifestURL)

                let backupURL = journal.folder.appendingPathComponent(record.backupPath)
                let originalBytes = try readOrInterrupt(backupURL)
                guard StoreFileHashing.sha256Hex(originalBytes) == record.originalHash else {
                    throw StoreMigrationError.backupMismatch(store: storeNamed(record.store))
                }
                try files.writeAtomic(originalBytes, to: storeURL(for: record))
                guard StoreFileHashing.sha256Hex(try readOrInterrupt(storeURL(for: record))) == record.originalHash else {
                    throw StoreMigrationError.interrupted
                }
            }

            journal.manifest.status = .rolledBack
            try writeManifest(journal.manifest, to: journal.manifestURL)
            return .rolledBack(
                migrationID: migrationID,
                stores: journal.manifest.stores.compactMap { StoreName(rawValue: $0.store) }
            )
        } catch let error as StoreMigrationError {
            return .failed(message:error.safeMessage)
        } catch {
            return .failed(message:StoreMigrationError.interrupted.safeMessage)
        }
    }

    // MARK: Byte classification and staging

    private enum ByteState {
        case original
        case target
    }

    private func classifyBytes(for record: StoreMigrationRecord) throws -> ByteState {
        let url = storeURL(for: record)
        guard files.exists(url) else {
            throw StoreMigrationError.externalByteChange(store: storeNamed(record.store))
        }
        let hash = StoreFileHashing.sha256Hex(try readOrInterrupt(url))
        if hash == record.originalHash { return .original }
        if hash == record.targetHash { return .target }
        throw StoreMigrationError.externalByteChange(store: storeNamed(record.store))
    }

    /// Classifies one present store file during preflight. Missing and
    /// already-current stores yield `nil`; legacy stores yield a plan holding
    /// the exact original bytes and the staged version-1 envelope bytes.
    private func classifyStore(_ store: StoreName) throws -> MigrationPlan? {
        let url = storeURL(for: store)
        guard files.exists(url) else { return nil }
        let data: Data
        do {
            data = try files.data(at: url)
        } catch {
            throw StoreMigrationError.storeRejected(message: StoreHealthMessages.loadFailed(store))
        }
        switch store {
        case .events:
            return try makePlan(data, store: store, as: [EvidenceEvent].self)
        case .corrections:
            return try makePlan(data, store: store, as: [AttributionCorrection].self)
        case .reports:
            return try makePlan(data, store: store, as: [DailyReport].self)
        case .settings:
            return try makePlan(data, store: store, as: AppSettings.self)
        case .manifests:
            return try makePlan(data, store: store, as: [SourceKind: SourceManifest].self)
        case .sessions:
            return try makePlan(data, store: store, as: [WorkSession].self)
        case .conversations:
            return try makePlan(data, store: store, as: [StoredConversation].self)
        }
    }

    private func makePlan<T: Codable & Equatable>(
        _ data: Data,
        store: StoreName,
        as type: T.Type
    ) throws -> MigrationPlan? {
        do {
            let contents = try StoreFileReader.readWithGeneration(data, store: store, as: type)
            guard contents.generation == .legacy else { return nil }
            let target = try validateStagedBytes(
                try StoreFileWriter.envelopeData(payload: contents.payload, store: store),
                store: store,
                expectedPayload: contents.payload,
                as: type
            )
            return MigrationPlan(store: store, originalBytes: data, targetBytes: target)
        } catch let error as StoreMigrationError {
            throw error
        } catch let rejection as StoreFileRejection {
            throw StoreMigrationError.storeRejected(message: rejection.userMessage(for: store))
        } catch {
            throw StoreMigrationError.storeRejected(message: StoreHealthMessages.loadFailed(store))
        }
    }

    /// Rebuilds the staged version-1 envelope bytes for one participant from
    /// its current on-disk bytes and validates them by decoding back.
    private func stagedBytes(for store: StoreName, from bytes: Data, isOriginal: Bool) throws -> Data {
        switch store {
        case .events:
            return try stage(bytes, store: store, as: [EvidenceEvent].self, isOriginal: isOriginal)
        case .corrections:
            return try stage(bytes, store: store, as: [AttributionCorrection].self, isOriginal: isOriginal)
        case .reports:
            return try stage(bytes, store: store, as: [DailyReport].self, isOriginal: isOriginal)
        case .settings:
            return try stage(bytes, store: store, as: AppSettings.self, isOriginal: isOriginal)
        case .manifests:
            return try stage(bytes, store: store, as: [SourceKind: SourceManifest].self, isOriginal: isOriginal)
        case .sessions:
            return try stage(bytes, store: store, as: [WorkSession].self, isOriginal: isOriginal)
        case .conversations:
            return try stage(bytes, store: store, as: [StoredConversation].self, isOriginal: isOriginal)
        }
    }

    private func stage<T: Codable & Equatable>(
        _ bytes: Data,
        store: StoreName,
        as type: T.Type,
        isOriginal: Bool
    ) throws -> Data {
        do {
            if isOriginal {
                let contents = try StoreFileReader.readWithGeneration(bytes, store: store, as: type)
                guard contents.generation == .legacy else {
                    throw StoreMigrationError.manifestConflict(store: store)
                }
                return try validateStagedBytes(
                    try StoreFileWriter.envelopeData(payload: contents.payload, store: store),
                    store: store,
                    expectedPayload: contents.payload,
                    as: type
                )
            } else {
                let payload = try StoreFileReader.read(bytes, store: store, as: type)
                return try validateStagedBytes(
                    try StoreFileWriter.envelopeData(payload: payload, store: store),
                    store: store,
                    expectedPayload: payload,
                    as: type
                )
            }
        } catch let error as StoreMigrationError {
            throw error
        } catch {
            throw StoreMigrationError.manifestConflict(store: store)
        }
    }

    /// A staged envelope is valid only when it decodes as a current-version
    /// envelope for this store and its payload survives the round trip
    /// unchanged — payload equality is checked, never assumed.
    private func validateStagedBytes<T: Codable & Equatable>(
        _ staged: Data,
        store: StoreName,
        expectedPayload: T,
        as type: T.Type
    ) throws -> Data {
        do {
            let roundTripped = try StoreFileReader.read(staged, store: store, as: type)
            guard roundTripped == expectedPayload else {
                throw StoreMigrationError.stagedValidationFailed(store: store)
            }
        } catch let error as StoreMigrationError {
            throw error
        } catch {
            throw StoreMigrationError.stagedValidationFailed(store: store)
        }
        return staged
    }

    // MARK: Helpers

    private func storeURL(for store: StoreName) -> URL {
        directory.appendingPathComponent(store.fileName)
    }

    private func storeURL(for record: StoreMigrationRecord) -> URL {
        storeURL(for: StoreName(rawValue: record.store) ?? .events)
    }

    private func storeNamed(_ rawValue: String) -> StoreName {
        StoreName(rawValue: rawValue) ?? .events
    }

    private func journalID(_ journal: Journal) throws -> UUID {
        guard let id = UUID(uuidString: journal.manifest.migrationID) else {
            throw StoreMigrationError.manifestUnreadable
        }
        return id
    }

    private func readOrInterrupt(_ url: URL) throws -> Data {
        do {
            return try files.data(at: url)
        } catch {
            throw StoreMigrationError.interrupted
        }
    }

    /// Manifests are deterministic sorted JSON, written atomically, and every
    /// write journals a phase or a per-store flag before the matching
    /// mutation.
    private func writeManifest(_ manifest: StoreMigrationManifest, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(manifest)
        } catch {
            throw StoreMigrationError.manifestUnreadable
        }
        do {
            try files.writeAtomic(data, to: url)
        } catch {
            throw StoreMigrationError.interrupted
        }
    }
}
