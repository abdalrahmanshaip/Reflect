import Foundation
@testable import ReflectLib

/// Task B regression coverage: published state may only advance after the
/// corresponding store write succeeds. Every fixture is synthetic and lives in
/// a fresh temporary directory; nothing here touches real user data, the
/// Keychain, or the network.
struct SaveOrderTests {
    static let suiteName = "SaveOrderTests"
    private let dayKey = "2026-01-05"

    @MainActor
    private func makeAppStore(directory: URL, home: URL? = nil) -> AppStore {
        AppStore(
            persistence: PersistenceController(directory: directory),
            secrets: MemorySecretStore(),
            home: home ?? Fixtures.makeTempDirectory(directory.lastPathComponent + "-home"),
            analysisAvailabilityProvider: { @Sendable () async -> [AnalysisAgentStatus] in [] }
        )
    }

    /// Makes the store directory unwritable AFTER loading, mirroring a disk
    /// that turns hostile while the app is running.
    private func obstructStoreDirectory(_ directory: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: directory.path
        )
    }

    private func restoreStoreDirectory(_ directory: URL) {
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: directory.path
        )
    }

    @MainActor
    private func makeComposer(store: AppStore, day: String) -> ReflectionDraftModel {
        ReflectionDraftModel(
            dayKey: day,
            report: store.report(for: day),
            questions: [],
            save: { store.saveReport($0) }
        )
    }

    /// A failed report save must not publish the reflection: the report
    /// collection stays at the last successful revision, the failed day is not
    /// marked reflected, and the draft text stays in the composer.
    @MainActor
    func failedReportSaveDoesNotPublishReflection() throws {
        let directory = Fixtures.makeTempDirectory("save-order-failed-report")
        let store = makeAppStore(directory: directory)
        let noteID = ReflectionDraftModel.noteAnswerID(for: dayKey)

        // Baseline: one successful revision while the store is healthy.
        let composer = makeComposer(store: store, day: dayKey)
        composer.updateText("First saved synthetic revision.", for: noteID)
        try expectTrue(composer.saveNow(), "the first save must succeed on a healthy store")
        try expectEqual(store.reports.count, 1)
        let lastSuccessfulRevision = store.reports[0]

        try obstructStoreDirectory(directory)
        defer { restoreStoreDirectory(directory) }

        // A fresh day's reflection cannot be written.
        let freshDay = "2026-01-06"
        let freshNoteID = ReflectionDraftModel.noteAnswerID(for: freshDay)
        let freshDraft = "Synthetic draft for a day whose save must fail."
        let freshComposer = makeComposer(store: store, day: freshDay)
        freshComposer.updateText(freshDraft, for: freshNoteID)
        let freshAccepted = freshComposer.saveNow()

        try expectFalse(freshAccepted, "a save over an unwritable store directory must not claim success")
        guard case .failed = freshComposer.saveState else {
            throw TestFailure("expected a failed save state, got \(freshComposer.saveState)")
        }
        try expectEqual(store.reports.count, 1, "a failed save must not add or publish a report")
        try expectFalse(
            DayOverviewBuilder.isReflected(store.report(for: freshDay)),
            "a failed save must not mark the day reflected"
        )
        try expectFalse(store.dayOverview(for: freshDay).reflected, "the day overview must not claim a failed reflection")
        try expectEqual(freshComposer.text(for: freshNoteID), freshDraft, "the draft text must survive the failed save")
        try expectTrue(store.lastError != nil, "a failed save must surface a visible error")

        // The stored day keeps exactly its last successful revision.
        composer.updateText("Second synthetic revision that cannot be written.", for: noteID)
        let secondAccepted = composer.saveNow()
        try expectFalse(secondAccepted, "the second failed save must not claim success")
        try expectEqual(store.reports.count, 1, "a failed replacement must not publish a second revision")
        try expectEqual(store.reports[0].updatedAt, lastSuccessfulRevision.updatedAt,
                        "a failed save must not advance the last successful revision")
        try expectEqual(store.reports[0].answers[noteID]?.text, "First saved synthetic revision.",
                        "a failed save must not replace the stored answer text")

        guard case .loaded(let diskReports) = PersistenceController(directory: directory).loadReportsHealth() else {
            throw TestFailure("expected the reports store to stay readable after failed saves")
        }
        try expectEqual(diskReports.count, 1, "disk must keep exactly the last successful revision")
    }

    /// A failed report save must surface a safe message: it may name the
    /// affected store and the retry path, but never the underlying OS error
    /// text, store file names, temp identifiers, or private paths.
    @MainActor
    func failedReportSaveErrorStaysSafe() throws {
        let directory = Fixtures.makeTempDirectory("save-order-safe-error")
        let store = makeAppStore(directory: directory)
        let noteID = ReflectionDraftModel.noteAnswerID(for: dayKey)

        let composer = makeComposer(store: store, day: dayKey)
        try obstructStoreDirectory(directory)
        defer { restoreStoreDirectory(directory) }

        composer.updateText("Synthetic draft whose failure must surface a safe message.", for: noteID)
        let accepted = composer.saveNow()

        try expectFalse(accepted, "the save must fail while the store directory is unwritable")
        let message = try require(store.lastError, "a failed save must surface an error message")
        try expectFalse(message.contains(directory.path), "the message must not include the private store path")
        try expectFalse(message.contains("reports.json"), "the message must not include the store file name")
        try expectFalse(message.contains(".tmp-"), "the message must not include OS temp file identifiers")
        try expectFalse(message.contains("permission"), "the message must not relay raw OS error text")
        try expectTrue(message.contains("composer"), "the report message must say the reflection stays in the composer")
    }

    /// Restoring write permission and retrying preserves the exact draft and
    /// stores exactly one durable revision — never a duplicate.
    @MainActor
    func retryReportSavePreservesDraft() throws {
        let directory = Fixtures.makeTempDirectory("save-order-retry")
        let store = makeAppStore(directory: directory)
        let noteID = ReflectionDraftModel.noteAnswerID(for: dayKey)
        let exactDraft = "Synthetic draft that outlives a failed save verbatim."

        let composer = makeComposer(store: store, day: dayKey)
        try obstructStoreDirectory(directory)
        composer.updateText(exactDraft, for: noteID)
        let firstAttempt = composer.saveNow()

        try expectFalse(firstAttempt, "the first attempt must fail while the store directory is unwritable")
        try expectTrue(store.reports.isEmpty, "a failed save must not publish a report before the retry")
        try expectFalse(
            DayOverviewBuilder.isReflected(store.report(for: dayKey)),
            "a failed save must not mark the day reflected"
        )
        try expectEqual(composer.text(for: noteID), exactDraft, "the exact draft text must survive the failed save")

        restoreStoreDirectory(directory)
        defer { restoreStoreDirectory(directory) }

        let retryAccepted = composer.saveNow()
        try expectTrue(retryAccepted, "a retry after the directory is writable again must succeed")
        try expectEqual(store.reports.count, 1, "the retry must produce one stored report, not duplicates")
        try expectEqual(store.reports.first?.day, dayKey)
        try expectEqual(store.reports.first?.answers[noteID]?.text, exactDraft, "the retry stores the exact draft")
        guard case .saved = composer.saveState else {
            throw TestFailure("expected a saved state after the successful retry, got \(composer.saveState)")
        }

        // Saving again replaces the same revision; it never appends.
        try expectTrue(composer.saveNow(), "a second save stays successful")
        try expectEqual(store.reports.count, 1, "repeated saves must replace, never duplicate")

        // The durable copy reloads as exactly one reflected revision.
        let reopened = makeAppStore(directory: directory)
        try expectEqual(reopened.reports.count, 1, "the reopened store holds exactly one revision")
        try expectEqual(reopened.reports.first?.answers[noteID]?.text, exactDraft)
        try expectTrue(DayOverviewBuilder.isReflected(reopened.report(for: dayKey)),
                       "the day is reflected from the durable copy")
    }

    /// A failed preference write must not leave a visible successful value
    /// that differs from disk; retrying the same change converges both.
    /// Controls reach the store only through `updateSettings`, which stages
    /// the candidate and publishes it only after the write succeeds.
    @MainActor
    func failedSettingsUpdateDoesNotPublishDivergentValue() throws {
        let directory = Fixtures.makeTempDirectory("save-order-failed-settings")
        let store = makeAppStore(directory: directory)
        let persistence = PersistenceController(directory: directory)

        try obstructStoreDirectory(directory)
        defer { restoreStoreDirectory(directory) }

        let accepted = store.updateSettings { $0.aiEnabled = true }

        try expectFalse(accepted, "a preference write over an unwritable store must not claim success")
        try expectFalse(store.settings.aiEnabled, "a failed preference write must not stay published")
        try expectTrue(store.lastError != nil, "a failed preference write must surface an error")

        switch persistence.loadSettingsHealth() {
        case .missing:
            break
        case .loaded(let diskSettings):
            try expectFalse(diskSettings.aiEnabled, "disk must stay the source of truth after a failed write")
        case .failed:
            throw TestFailure("expected a readable settings store after a failed write")
        }

        restoreStoreDirectory(directory)
        let retryAccepted = store.updateSettings { $0.aiEnabled = true }
        try expectTrue(retryAccepted, "the retry after recovery must succeed")
        try expectTrue(store.settings.aiEnabled, "the retry publishes the preference")
        guard case .loaded(let diskAfter) = persistence.loadSettingsHealth() else {
            throw TestFailure("expected a readable settings store after the successful retry")
        }
        try expectTrue(diskAfter.aiEnabled, "the retry converges disk with the published value")
    }

    /// A failed correction write must not publish the correction, and a retry
    /// after recovery converges the published collection with disk.
    @MainActor
    func failedCorrectionSaveDoesNotPublishCorrection() throws {
        let directory = Fixtures.makeTempDirectory("save-order-failed-correction")
        let store = makeAppStore(directory: directory)
        let persistence = PersistenceController(directory: directory)

        try obstructStoreDirectory(directory)
        defer { restoreStoreDirectory(directory) }

        store.setCorrection(.agent, for: "fixture-event-1")

        try expectTrue(store.corrections.isEmpty, "a failed correction write must not publish the correction")
        try expectTrue(store.lastError != nil, "a failed correction write must surface an error")
        switch persistence.loadCorrectionsHealth() {
        case .missing:
            break
        case .loaded(let diskCorrections):
            try expectTrue(diskCorrections.isEmpty, "disk must not hold a correction that was never saved")
        case .failed:
            throw TestFailure("expected a readable corrections store after a failed write")
        }

        restoreStoreDirectory(directory)
        store.setCorrection(.agent, for: "fixture-event-1")
        try expectEqual(store.corrections.count, 1, "the retry publishes exactly one correction")
        guard case .loaded(let diskAfter) = persistence.loadCorrectionsHealth() else {
            throw TestFailure("expected a readable corrections store after the successful retry")
        }
        try expectEqual(diskAfter.count, 1, "the retry stores exactly one correction on disk")
        try expectEqual(diskAfter.first?.eventId, "fixture-event-1")

        // A removal through the same path round-trips to disk as well.
        store.setCorrection(nil, for: "fixture-event-1")
        try expectTrue(store.corrections.isEmpty, "the removal publishes an empty collection")
        guard case .loaded(let diskCleared) = persistence.loadCorrectionsHealth() else {
            throw TestFailure("expected a readable corrections store after the removal")
        }
        try expectTrue(diskCleared.isEmpty, "the removal must reach disk too")
    }

    /// When the events write fails, the new records stay unpublished and the
    /// source's previous durable coverage and manifest stay accurate and
    /// unchanged. The failure is retained as a retryable per-source outcome;
    /// a successful retry replaces that failure state, makes the outcome
    /// durable once, and further imports deduplicate.
    @MainActor
    func failedImportKeepsEventsAndManifestUnpublished() throws {
        let directory = Fixtures.makeTempDirectory("save-order-failed-import")
        let home = Fixtures.makeTempDirectory("save-order-failed-import-home")
        Fixtures.codexSessionTree(in: home)
        let store = makeAppStore(directory: directory, home: home)
        let persistence = PersistenceController(directory: directory)
        try expectTrue(store.events.isEmpty, "the fixture starts without imported events")

        // Baseline: one durable import establishes real coverage.
        store.importSource(.codex)
        try waitForImportToSettle(store)
        let durableEvents = store.events
        try expectTrue(durableEvents.count > 0, "the baseline import is durable")
        let baselineManifest = try require(store.manifests[.codex], "the baseline import advances the manifest")
        try expectEqual(baselineManifest.importedEventCount, durableEvents.count,
                        "baseline coverage matches the published events")
        let eventsBytesBefore = try Data(contentsOf: directory.appendingPathComponent("events.json"))
        let manifestsBytesBefore = try Data(contentsOf: directory.appendingPathComponent("manifests.json"))

        // A second synthetic session appears, so the next import has new work.
        let secondSession = home
            .appendingPathComponent(".codex/sessions/2026/01/05", isDirectory: true)
            .appendingPathComponent("rollout-2026-01-05T10-00-00-fixture-two.jsonl")
        Fixtures.write(Fixtures.codexFixtureText, to: secondSession)

        try obstructStoreDirectory(directory)
        defer { restoreStoreDirectory(directory) }

        store.importSource(.codex)
        try waitForImportToSettle(store)

        // The failed attempt changes nothing durable and stays retryable.
        try expectEqual(store.events.count, durableEvents.count,
                        "a failed events write must not publish the new records")
        let manifestAfterFailure = try require(store.manifests[.codex], "the previous manifest coverage stays visible")
        try expectEqual(manifestAfterFailure, baselineManifest,
                        "the previous durable coverage and manifest must stay accurate and unchanged")
        try expectEqual(try Data(contentsOf: directory.appendingPathComponent("events.json")), eventsBytesBefore,
                        "the events store bytes stay unchanged")
        try expectEqual(try Data(contentsOf: directory.appendingPathComponent("manifests.json")), manifestsBytesBefore,
                        "the manifests store bytes stay unchanged")
        try expectTrue(store.lastError != nil, "the failed import must surface an error")
        try expectFalse(store.lastImportSummary?.contains("added") == true,
                        "the import summary must not claim records were added")
        let failureResult = try require(store.importResults[.codex], "the failed source must retain its keyed result")
        try expectEqual(failureResult.status, .retryableSaveFailure)
        try expectTrue(failureResult.message.contains("not saved"),
                       "the keyed result must say nothing was saved, got: \(failureResult.message)")
        try expectTrue(failureResult.message.contains("Try importing again"),
                       "the keyed result must stay retryable, got: \(failureResult.message)")

        restoreStoreDirectory(directory)
        store.importSource(.codex)
        try waitForImportToSettle(store)

        // The successful retry replaces the failure state and deduplicates.
        try expectTrue(store.events.count > durableEvents.count, "the retry imports the second session's new records")
        let codexCount = store.events.filter { $0.sourceKind == .codex }.count
        try expectEqual(codexCount, store.events.count, "only the imported source's events are published")
        let manifest = try require(store.manifests[.codex], "the durable import advances the manifest")
        try expectTrue(manifest.lastImport != nil, "the manifest records the durable import")
        try expectEqual(manifest.importedEventCount, codexCount, "the manifest count matches the published events")
        let retryResult = try require(store.importResults[.codex], "the retry must retain its own keyed result")
        try expectEqual(retryResult.status, .imported, "the successful retry replaces the failure state")

        guard case .loaded(let diskEvents) = persistence.loadEventsHealth() else {
            throw TestFailure("expected a readable events store after the successful import")
        }
        try expectEqual(diskEvents.count, store.events.count, "disk holds the durable copy")

        let durableCount = store.events.count
        store.importSource(.codex)
        try waitForImportToSettle(store)
        try expectEqual(store.events.count, durableCount, "re-importing the same evidence must deduplicate")
        let dedupedResult = try require(store.importResults[.codex], "the deduplicated run retains its keyed result")
        try expectEqual(dedupedResult.status, .imported)
        try expectEqual(dedupedResult.addedCount, 0, "the deduplicated import adds nothing")
    }

    @MainActor
    private func waitForImportToSettle(_ store: AppStore, timeout: TimeInterval = 10) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !store.importing.isEmpty && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        try expectTrue(store.importing.isEmpty, "the import did not settle before the \(Int(timeout))s timeout")
    }

    static var entries: [TestEntry] {
        let tests = SaveOrderTests()
        return [
            TestEntry(suite: suiteName, name: "failedReportSaveDoesNotPublishReflection") {
                try MainActor.assumeIsolated { try tests.failedReportSaveDoesNotPublishReflection() }
            },
            TestEntry(suite: suiteName, name: "retryReportSavePreservesDraft") {
                try MainActor.assumeIsolated { try tests.retryReportSavePreservesDraft() }
            },
            TestEntry(suite: suiteName, name: "failedReportSaveErrorStaysSafe") {
                try MainActor.assumeIsolated { try tests.failedReportSaveErrorStaysSafe() }
            },
            TestEntry(suite: suiteName, name: "failedSettingsUpdateDoesNotPublishDivergentValue") {
                try MainActor.assumeIsolated { try tests.failedSettingsUpdateDoesNotPublishDivergentValue() }
            },
            TestEntry(suite: suiteName, name: "failedCorrectionSaveDoesNotPublishCorrection") {
                try MainActor.assumeIsolated { try tests.failedCorrectionSaveDoesNotPublishCorrection() }
            },
            TestEntry(suite: suiteName, name: "failedImportKeepsEventsAndManifestUnpublished") {
                try MainActor.assumeIsolated { try tests.failedImportKeepsEventsAndManifestUnpublished() }
            }
        ]
    }
}
