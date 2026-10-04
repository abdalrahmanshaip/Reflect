import Foundation
@testable import ReflectLib

/// Task E regression coverage: eligibility is decided once at the scheduling
/// boundary — before any source adapter or content read is scheduled — and
/// every source that actually ran keeps its own safe, keyed result. All
/// fixtures are synthetic and live in temporary directories; injected
/// executors read nothing from disk, and no real CLI, AI provider, network,
/// or the normal app is ever involved.
struct ImportSchedulingTests {
    static let suiteName = "ImportSchedulingTests"

    /// Thread-safe recorder for the scheduling boundary: the source kinds that
    /// actually reached the content-reading executor.
    final class ExecutorRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var scheduled: [SourceKind] = []

        func record(_ kind: SourceKind) {
            lock.lock()
            scheduled.append(kind)
            lock.unlock()
        }

        var kinds: [SourceKind] {
            lock.lock()
            defer { lock.unlock() }
            return scheduled
        }

        func contains(_ kind: SourceKind) -> Bool { kinds.contains(kind) }
    }

    /// Deterministic completion ordering: the gated source's executor returns
    /// only after the test opens the gate, so its result is published strictly
    /// after the other source's result already exists.
    final class CompletionGate: @unchecked Sendable {
        private let semaphore = DispatchSemaphore(value: 0)
        func wait(seconds: TimeInterval) -> Bool {
            semaphore.wait(timeout: .now() + seconds) == .success
        }
        func open() { semaphore.signal() }
    }

    @MainActor
    private func makeAppStore(
        directory: URL,
        home: URL,
        executor: ImportSourceExecutor? = nil
    ) -> AppStore {
        AppStore(
            persistence: PersistenceController(directory: directory),
            secrets: MemorySecretStore(),
            home: home,
            analysisAvailabilityProvider: { @Sendable () async -> [AnalysisAgentStatus] in [] },
            importExecutor: executor
        )
    }

    /// Builds synthetic events for one source. Stable ids come from the prefix,
    /// so repeated runs with the same prefix deduplicate.
    private static func syntheticEvents(kind: SourceKind, idPrefix: String, count: Int) -> [EvidenceEvent] {
        (0..<count).map { i in
            EvidenceEvent(
                id: "\(idPrefix)-\(i)",
                sourceKind: kind,
                sourceName: kind.displayName,
                timestamp: Fixtures.referenceDate.addingTimeInterval(TimeInterval(i * 60)),
                timestampApproximate: false,
                kind: .agentMessage,
                summary: "Synthetic \(kind.displayName) record \(i)",
                detail: "",
                evidencePath: "/tmp/reflect-synthetic-fixture/\(kind.rawValue)-\(i).jsonl",
                evidenceLine: i + 1,
                observedAttribution: .agent,
                observedAttributionNote: "Structural role in a synthetic transcript",
                importedAt: Fixtures.referenceDate
            )
        }
    }

    private static func recordingExecutor(
        _ recorder: ExecutorRecorder,
        eventsPerSource: Int = 0
    ) -> ImportSourceExecutor {
        return { kind, _, _ in
            recorder.record(kind)
            return ImportOutcome(
                kind: kind,
                events: Self.syntheticEvents(kind: kind, idPrefix: "run-\(kind.rawValue)", count: eventsPerSource),
                filesScanned: eventsPerSource > 0 ? 1 : 0,
                note: nil
            )
        }
    }

    private static func makeUnverifiedStore(in home: URL, app: String) {
        let ws = home.appendingPathComponent("Library/Application Support/\(app)/User/workspaceStorage/ws1", isDirectory: true)
        try! FileManager.default.createDirectory(at: ws, withIntermediateDirectories: true)
        Fixtures.write("synthetic unverified store bytes", to: ws.appendingPathComponent("state.vscdb"))
    }

    @MainActor
    private func waitForImportToSettle(_ store: AppStore, timeout: TimeInterval = 10) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !store.importing.isEmpty && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        try expectTrue(store.importing.isEmpty, "the import did not settle before the \(Int(timeout))s timeout")
    }

    @MainActor
    private func waitForCondition(
        _ condition: @MainActor () -> Bool,
        timeout: TimeInterval = 10,
        message: String
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        try expectTrue(condition(), message)
    }

    // MARK: Pure eligibility decision

    /// The single eligibility decision: bulk scheduling needs detected
    /// availability on top of enabled/verified/not-in-flight, and Git needs an
    /// explicitly selected repository; single-source scheduling may still run
    /// a missing source for its honest feedback, but never a disabled or
    /// unverified one.
    func eligibilityDecisionCoversScopesAndGates() throws {
        let enabled: Set<SourceKind> = [.codex, .cursor, .gitLocal]
        let detected = SourceAvailability(status: .detected, fileCount: 1, rootPath: nil, lastModified: nil, note: nil)
        let missing = SourceAvailability(status: .missing, fileCount: 0, rootPath: nil, lastModified: nil, note: nil)
        let manual = SourceAvailability(status: .manual, fileCount: 1, rootPath: "/tmp/reflect-fixture/repo", lastModified: nil, note: nil)
        let unverified = SourceAvailability(status: .detectedUnverified, fileCount: 1, rootPath: nil, lastModified: nil, note: nil)

        // Bulk: detected, enabled, verified, not-in-flight only.
        try expectTrue(ImportRules.isImportEligible(
            kind: .codex, scope: .bulkImport, importing: [],
            enabledSources: enabled, gitRepositoryPath: nil,
            formatVerified: true, availability: detected
        ))
        try expectFalse(ImportRules.isImportEligible(
            kind: .codex, scope: .bulkImport, importing: [],
            enabledSources: enabled, gitRepositoryPath: nil,
            formatVerified: true, availability: missing
        ), "bulk import must not schedule a missing source")
        try expectFalse(ImportRules.isImportEligible(
            kind: .codex, scope: .bulkImport, importing: [],
            enabledSources: enabled, gitRepositoryPath: nil,
            formatVerified: true, availability: nil
        ), "bulk import must not schedule a source without availability metadata")
        try expectFalse(ImportRules.isImportEligible(
            kind: .codex, scope: .bulkImport, importing: [],
            enabledSources: enabled, gitRepositoryPath: nil,
            formatVerified: true, availability: manual
        ), "bulk sources require detected availability, not a manual marker")
        try expectFalse(ImportRules.isImportEligible(
            kind: .codex, scope: .bulkImport, importing: [.codex],
            enabledSources: enabled, gitRepositoryPath: nil,
            formatVerified: true, availability: detected
        ), "bulk import must not schedule an in-flight source twice")
        try expectFalse(ImportRules.isImportEligible(
            kind: .codex, scope: .bulkImport, importing: [],
            enabledSources: [], gitRepositoryPath: nil,
            formatVerified: true, availability: detected
        ), "bulk import must not schedule a disabled source")
        try expectFalse(ImportRules.isImportEligible(
            kind: .cursor, scope: .bulkImport, importing: [],
            enabledSources: enabled, gitRepositoryPath: nil,
            formatVerified: false, availability: unverified
        ), "bulk import must not schedule an unverified format")

        // Git: eligibility hinges on an explicitly selected repository.
        try expectTrue(ImportRules.isImportEligible(
            kind: .gitLocal, scope: .bulkImport, importing: [],
            enabledSources: enabled, gitRepositoryPath: "/tmp/reflect-fixture/repo",
            formatVerified: true, availability: manual
        ))
        try expectFalse(ImportRules.isImportEligible(
            kind: .gitLocal, scope: .bulkImport, importing: [],
            enabledSources: enabled, gitRepositoryPath: nil,
            formatVerified: true, availability: missing
        ), "bulk import must not schedule git without a selected repository")
        try expectFalse(ImportRules.isImportEligible(
            kind: .gitLocal, scope: .bulkImport, importing: [],
            enabledSources: enabled, gitRepositoryPath: "",
            formatVerified: true, availability: missing
        ), "an empty repository path is not a selection")
        try expectFalse(ImportRules.isImportEligible(
            kind: .gitLocal, scope: .bulkImport, importing: [],
            enabledSources: enabled, gitRepositoryPath: "/tmp/reflect-fixture/missing-repo",
            formatVerified: true, availability: missing
        ), "bulk import must not schedule a selected repository that is not available")

        // Single-source: disabled and unverified stay rejected; a missing
        // source may still run for its honest "not detected" feedback.
        try expectTrue(ImportRules.isImportEligible(
            kind: .codex, scope: .singleSource, importing: [],
            enabledSources: enabled, gitRepositoryPath: nil,
            formatVerified: true, availability: missing
        ))
        try expectFalse(ImportRules.isImportEligible(
            kind: .cursor, scope: .singleSource, importing: [],
            enabledSources: enabled, gitRepositoryPath: nil,
            formatVerified: false, availability: unverified
        ), "an unverified format must be rejected before scheduling")
        try expectFalse(ImportRules.isImportEligible(
            kind: .codex, scope: .singleSource, importing: [],
            enabledSources: [], gitRepositoryPath: nil,
            formatVerified: true, availability: detected
        ), "a disabled source must be rejected before scheduling")
        try expectFalse(ImportRules.isImportEligible(
            kind: .codex, scope: .singleSource, importing: [.codex],
            enabledSources: enabled, gitRepositoryPath: nil,
            formatVerified: true, availability: detected
        ), "an in-flight source must not start again")
    }

    // MARK: Bulk scheduling at the boundary

    /// Bulk import schedules exactly the enabled, verified, detected sources;
    /// disabled, unverified, missing, and unselected-git kinds never reach the
    /// content-reading executor.
    @MainActor
    func bulkImportSchedulesOnlyEligibleSources() throws {
        let home = Fixtures.makeTempDirectory("bulk-eligible-home")
        Fixtures.codexSessionTree(in: home)
        Fixtures.claudeProjectTree(in: home)
        Fixtures.copilotTree(in: home)
        Self.makeUnverifiedStore(in: home, app: "Cursor")
        Self.makeUnverifiedStore(in: home, app: "Code")

        let recorder = ExecutorRecorder()
        let store = makeAppStore(
            directory: Fixtures.makeTempDirectory("bulk-eligible-store"),
            home: home,
            executor: Self.recordingExecutor(recorder)
        )

        store.importAllAvailable()
        try waitForImportToSettle(store)

        try expectEqual(
            Set(recorder.kinds),
            Set([.codex, .claudeCode, .copilotCLI]),
            "bulk import must schedule exactly the detected, verified, enabled sources"
        )
    }

    /// Enabled, verified sources without detected availability are never
    /// scanned or read by a bulk import.
    @MainActor
    func bulkImportSkipsMissingSources() throws {
        let home = Fixtures.makeTempDirectory("bulk-missing-home")
        Fixtures.codexSessionTree(in: home)

        let recorder = ExecutorRecorder()
        let store = makeAppStore(
            directory: Fixtures.makeTempDirectory("bulk-missing-store"),
            home: home,
            executor: Self.recordingExecutor(recorder)
        )
        try expectEqual(store.availability[.claudeCode]?.status, .missing, "fixture precondition: claude code is missing")

        store.importAllAvailable()
        try waitForImportToSettle(store)

        try expectFalse(recorder.contains(.claudeCode), "a missing source must never reach the executor during bulk import")
        try expectFalse(recorder.contains(.copilotCLI), "a missing source must never reach the executor during bulk import")
        try expectFalse(recorder.contains(.cursor), "a missing unverified source must never reach the executor")
        try expectFalse(recorder.contains(.vscode), "a missing unverified source must never reach the executor")
        try expectFalse(recorder.contains(.gitLocal), "git without a selected repository must never be scheduled")
        try expectTrue(recorder.contains(.codex), "the detected source is scheduled")
        try expectEqual(recorder.kinds.count, 1, "exactly one eligible source is scheduled")
    }

    /// A disabled source is excluded from bulk scheduling even though it is
    /// present and detected on disk.
    @MainActor
    func bulkImportSkipsDisabledSources() throws {
        let home = Fixtures.makeTempDirectory("bulk-disabled-home")
        Fixtures.codexSessionTree(in: home)
        Fixtures.claudeProjectTree(in: home)

        let recorder = ExecutorRecorder()
        let store = makeAppStore(
            directory: Fixtures.makeTempDirectory("bulk-disabled-store"),
            home: home,
            executor: Self.recordingExecutor(recorder)
        )
        store.updateSettings { settings in
            _ = settings.enabledSources.remove(.codex)
        }

        store.importAllAvailable()
        try waitForImportToSettle(store)

        try expectFalse(recorder.contains(.codex), "a disabled source must never reach the executor during bulk import")
        try expectTrue(recorder.contains(.claudeCode), "the enabled detected source is scheduled")
    }

    /// Bulk import schedules Git only after a repository is explicitly selected.
    @MainActor
    func bulkImportExcludesGitUntilRepositorySelected() throws {
        let home = Fixtures.makeTempDirectory("bulk-git-home")
        Fixtures.codexSessionTree(in: home)
        let selectedRepo = Fixtures.makeTempDirectory("bulk-git-selected-repo")

        let recorder = ExecutorRecorder()
        let store = makeAppStore(
            directory: Fixtures.makeTempDirectory("bulk-git-store"),
            home: home,
            executor: Self.recordingExecutor(recorder)
        )

        store.importAllAvailable()
        try waitForImportToSettle(store)
        try expectFalse(recorder.contains(.gitLocal), "git without a selected repository must not be scheduled")

        store.updateSettings { settings in
            settings.gitRepositoryPath = home.appendingPathComponent("missing-repo").path
        }
        store.refreshAvailability()
        try expectEqual(store.availability[.gitLocal]?.status, .missing, "a selected but missing repository is unavailable")
        store.importAllAvailable()
        try waitForImportToSettle(store)
        try expectFalse(recorder.contains(.gitLocal), "a selected but missing repository must not reach the executor")

        store.updateSettings { settings in
            settings.gitRepositoryPath = selectedRepo.path
        }
        store.refreshAvailability()
        try expectEqual(store.availability[.gitLocal]?.status, .manual, "a selected repository is availability .manual")

        store.importAllAvailable()
        try waitForImportToSettle(store)
        try expectTrue(recorder.contains(.gitLocal), "git with an explicitly selected repository is scheduled")
    }

    // MARK: Single-source scheduling at the boundary

    /// An individual import of an unverified or disabled source is refused at
    /// the scheduling boundary: no adapter or content read is ever scheduled,
    /// and no result appears because nothing ran.
    @MainActor
    func singleSourceImportRejectsDisabledAndUnverifiedBeforeExecutor() throws {
        let home = Fixtures.makeTempDirectory("single-reject-home")
        Fixtures.codexSessionTree(in: home)
        Self.makeUnverifiedStore(in: home, app: "Cursor")

        let recorder = ExecutorRecorder()
        let store = makeAppStore(
            directory: Fixtures.makeTempDirectory("single-reject-store"),
            home: home,
            executor: Self.recordingExecutor(recorder)
        )

        // Unverified, detected, enabled: refused without scheduling.
        try expectEqual(store.availability[.cursor]?.status, .detectedUnverified)
        store.importSource(.cursor)
        try expectTrue(recorder.kinds.isEmpty, "an unverified source must never reach the executor")
        try expectTrue(store.importing.isEmpty, "an unverified source must not be scheduled")

        // Disabled, detected, verified: refused without scheduling.
        store.updateSettings { settings in
            _ = settings.enabledSources.remove(.codex)
        }
        store.importSource(.codex)
        try expectTrue(recorder.kinds.isEmpty, "a disabled source must never reach the executor")
        try expectTrue(store.importing.isEmpty, "a disabled source must not be scheduled")
        try expectTrue(store.importResults.isEmpty, "nothing ran, so no result may appear")
    }

    /// An eligible single-source import reaches the executor exactly once and
    /// retains its own keyed result.
    @MainActor
    func singleSourceImportRunsEligibleSourceAndRetainsResult() throws {
        let home = Fixtures.makeTempDirectory("single-eligible-home")
        Fixtures.codexSessionTree(in: home)

        let recorder = ExecutorRecorder()
        let store = makeAppStore(
            directory: Fixtures.makeTempDirectory("single-eligible-store"),
            home: home,
            executor: Self.recordingExecutor(recorder, eventsPerSource: 2)
        )

        store.importSource(.codex)
        try waitForImportToSettle(store)

        try expectEqual(recorder.kinds, [.codex], "one explicit request runs the source exactly once")
        let result = try require(store.importResults[.codex], "the source that ran must retain its own result")
        try expectEqual(result.status, .imported)
        try expectEqual(result.addedCount, 2)
        try expectEqual(store.events.count, 2, "the imported synthetic records are published")
    }

    /// A single-source import of a missing source keeps its honest per-source
    /// "not detected" feedback, which the single-source button allows today.
    @MainActor
    func singleSourceImportKeepsNotDetectedFeedback() throws {
        let home = Fixtures.makeTempDirectory("single-missing-home")
        let store = makeAppStore(
            directory: Fixtures.makeTempDirectory("single-missing-store"),
            home: home
        )

        store.importSource(.codex)
        try waitForImportToSettle(store)

        let result = try require(store.importResults[.codex], "the run must retain a per-source result")
        try expectEqual(result.status, .importerNote)
        try expectTrue(
            result.message.lowercased().contains("not detected"),
            "the per-source result must say the source was not detected, got: \(result.message)"
        )
        try expectTrue(store.events.isEmpty, "a missing source imports nothing")
    }

    /// Notes are adapter supplied display input. A private path or payload
    /// embedded in one must never be copied into the visible per-source result.
    func sourceNotesCannotLeakPathsIntoResults() throws {
        let privatePath = "/Users/example/private/repo/.git/index"
        let result = ImportSourceResult.completed(
            kind: .gitLocal,
            addedCount: 0,
            filesScanned: 0,
            note: "Git import failed: permission denied at \(privatePath)",
            manifestAdvanced: true
        )

        try expectEqual(result.status, .importerNote)
        try expectFalse(result.message.contains(privatePath), "per-source copy must not expose a private path")
        try expectTrue(result.message.contains("Check the selected repository"), "the sanitized result stays actionable")
    }

    // MARK: Keyed per-source results

    /// Results are keyed by source: a later completion never erases an earlier
    /// source's retained result, regardless of completion order.
    @MainActor
    func perSourceResultsSurviveOutOfOrderCompletions() throws {
        let home = Fixtures.makeTempDirectory("out-of-order-home")
        Fixtures.codexSessionTree(in: home)
        Fixtures.claudeProjectTree(in: home)

        let codexGate = CompletionGate()
        let recorder = ExecutorRecorder()
        let store = makeAppStore(
            directory: Fixtures.makeTempDirectory("out-of-order-store"),
            home: home,
            executor: { kind, _, _ in
                recorder.record(kind)
                if kind == .codex {
                    _ = codexGate.wait(seconds: 10)
                }
                return ImportOutcome(
                    kind: kind,
                    events: Self.syntheticEvents(
                        kind: kind,
                        idPrefix: "order-\(kind.rawValue)",
                        count: kind == .codex ? 2 : 3
                    ),
                    filesScanned: 1,
                    note: nil
                )
            }
        )

        store.importAllAvailable()

        // Claude Code (ungated) completes first while Codex is still in flight.
        try waitForCondition(
            { store.importResults[.claudeCode] != nil },
            message: "the ungated source must complete and retain its result first"
        )
        try expectTrue(store.importing.contains(.codex), "the gated source must still be in flight")
        try expectNil(store.importResults[.codex], "the gated source has no result yet")

        codexGate.open()
        try waitForImportToSettle(store)

        let codex = try require(store.importResults[.codex], "the later completion must retain its result")
        let claude = try require(store.importResults[.claudeCode], "the earlier completion must not be erased by the later one")
        try expectEqual(codex.status, .imported)
        try expectEqual(codex.addedCount, 2)
        try expectEqual(claude.status, .imported)
        try expectEqual(claude.addedCount, 3)
    }

    // MARK: Honest durability outcomes

    /// If events persist but the manifest write fails, the two durable
    /// outcomes stay honest: saved events remain published, the manifest does
    /// not advance, and the keyed result must not claim the manifest advanced.
    @MainActor
    func manifestSaveFailureKeepsEventsPublishedWithoutClaimingAdvance() throws {
        let directory = Fixtures.makeTempDirectory("manifest-failure-store")
        let manifestsURL = directory.appendingPathComponent("manifests.json")
        let damagedBytes = Data("{\"synthetic-damaged-manifests-fixture\":".utf8)
        try damagedBytes.write(to: manifestsURL)

        let home = Fixtures.makeTempDirectory("manifest-failure-home")
        Fixtures.codexSessionTree(in: home)

        let store = makeAppStore(directory: directory, home: home)
        try expectTrue(store.storeFailures[.manifests] != nil, "fixture precondition: the manifests store is damaged")
        let persistence = PersistenceController(directory: directory)

        store.importSource(.codex)
        try waitForImportToSettle(store)

        let publishedCount = store.events.count
        try expectTrue(publishedCount > 0, "the saved events must remain published")
        try expectNil(store.manifests[.codex], "the old manifest stays unchanged — nothing may claim it advanced")
        try expectTrue(store.lastError != nil, "the blocked manifest write must surface an error")

        let result = try require(store.importResults[.codex], "the source that ran must retain its keyed result")
        try expectEqual(result.status, .manifestSaveFailed)
        try expectTrue(
            result.message.contains("saved and shown"),
            "the result must say the records are saved and shown, got: \(result.message)"
        )
        try expectTrue(
            result.message.contains("could not be updated"),
            "the result must say the manifest could not be updated, got: \(result.message)"
        )
        if result.message.contains("added") {
            try expectTrue(
                result.message.contains("could not be updated"),
                "a result claiming added records must also disclose the failed manifest write, got: \(result.message)"
            )
        }

        // Disk keeps both honest outcomes: valid saved events, untouched damaged manifests.
        guard case .loaded(let diskEvents) = persistence.loadEventsHealth() else {
            throw TestFailure("expected the saved events to be durable on disk")
        }
        try expectEqual(diskEvents.count, publishedCount, "the saved events are durable")
        try expectEqual(try Data(contentsOf: manifestsURL), damagedBytes, "the blocked manifest write must not alter the old bytes")
    }

    static var entries: [TestEntry] {
        let tests = ImportSchedulingTests()
        return [
            TestEntry(suite: suiteName, name: "eligibilityDecisionCoversScopesAndGates") {
                try tests.eligibilityDecisionCoversScopesAndGates()
            },
            TestEntry(suite: suiteName, name: "bulkImportSchedulesOnlyEligibleSources") {
                try MainActor.assumeIsolated { try tests.bulkImportSchedulesOnlyEligibleSources() }
            },
            TestEntry(suite: suiteName, name: "bulkImportSkipsMissingSources") {
                try MainActor.assumeIsolated { try tests.bulkImportSkipsMissingSources() }
            },
            TestEntry(suite: suiteName, name: "bulkImportSkipsDisabledSources") {
                try MainActor.assumeIsolated { try tests.bulkImportSkipsDisabledSources() }
            },
            TestEntry(suite: suiteName, name: "bulkImportExcludesGitUntilRepositorySelected") {
                try MainActor.assumeIsolated { try tests.bulkImportExcludesGitUntilRepositorySelected() }
            },
            TestEntry(suite: suiteName, name: "singleSourceImportRejectsDisabledAndUnverifiedBeforeExecutor") {
                try MainActor.assumeIsolated { try tests.singleSourceImportRejectsDisabledAndUnverifiedBeforeExecutor() }
            },
            TestEntry(suite: suiteName, name: "singleSourceImportRunsEligibleSourceAndRetainsResult") {
                try MainActor.assumeIsolated { try tests.singleSourceImportRunsEligibleSourceAndRetainsResult() }
            },
            TestEntry(suite: suiteName, name: "singleSourceImportKeepsNotDetectedFeedback") {
                try MainActor.assumeIsolated { try tests.singleSourceImportKeepsNotDetectedFeedback() }
            },
            TestEntry(suite: suiteName, name: "sourceNotesCannotLeakPathsIntoResults") {
                try tests.sourceNotesCannotLeakPathsIntoResults()
            },
            TestEntry(suite: suiteName, name: "perSourceResultsSurviveOutOfOrderCompletions") {
                try MainActor.assumeIsolated { try tests.perSourceResultsSurviveOutOfOrderCompletions() }
            },
            TestEntry(suite: suiteName, name: "manifestSaveFailureKeepsEventsPublishedWithoutClaimingAdvance") {
                try MainActor.assumeIsolated { try tests.manifestSaveFailureKeepsEventsPublishedWithoutClaimingAdvance() }
            }
        ]
    }
}
