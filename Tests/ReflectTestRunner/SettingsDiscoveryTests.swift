import Foundation
@testable import ReflectLib

/// Shared, thread-safe probe for main-thread responsiveness checks.
/// Synthetic only: nothing here invokes a real agent CLI or reads real data.
final class DiscoveryProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var sawMainThreadValue = false
    private var mainProbeRanValue = false

    var sawMainThread: Bool {
        lock.lock(); defer { lock.unlock() }; return sawMainThreadValue
    }

    var mainProbeRan: Bool {
        lock.lock(); defer { lock.unlock() }; return mainProbeRanValue
    }

    func recordSawMainThread(_ value: Bool) {
        lock.lock(); sawMainThreadValue = value; lock.unlock()
    }

    /// Records whether the calling thread is the main thread. The thread check
    /// happens inside this synchronous method so it stays valid from async
    /// call sites.
    func recordSawMainThreadFromCurrentThread() {
        lock.lock(); sawMainThreadValue = Thread.isMainThread; lock.unlock()
    }

    func recordMainProbeRan() {
        lock.lock(); mainProbeRanValue = true; lock.unlock()
    }
}

/// Controllable fake availability provider for store-level tests. It never
/// spawns a process: a run is either immediate, delayed by a Task sleep off
/// the main actor, or held open on a gate the test releases explicitly.
final class FakeDiscoveryProvider: @unchecked Sendable {
    enum Mode {
        case immediate
        case delayed(TimeInterval)
        case gated
    }

    private let lock = NSLock()
    private let mode: Mode
    private var runCountValue = 0
    private var activeValue = 0
    private var maxActiveValue = 0
    private var ranOnMainThreadValue = false
    private var canceledRunCountValue = 0
    private var releasedValue = false
    private let gate = DispatchSemaphore(value: 0)

    init(mode: Mode = .immediate) {
        self.mode = mode
    }

    var runCount: Int {
        lock.lock(); defer { lock.unlock() }; return runCountValue
    }

    var maxConcurrentRuns: Int {
        lock.lock(); defer { lock.unlock() }; return maxActiveValue
    }

    var ranOnMainThread: Bool {
        lock.lock(); defer { lock.unlock() }; return ranOnMainThreadValue
    }

    /// Per-run cancellation count: how many runs observed task cancellation.
    /// Counting (not a sticky flag) lets a later run prove it completed
    /// un-canceled.
    var canceledRunCount: Int {
        lock.lock(); defer { lock.unlock() }; return canceledRunCountValue
    }

    func release() {
        lock.lock()
        releasedValue = true
        lock.unlock()
        gate.signal()
    }

    // Sync helpers so no locking or thread inspection happens directly in
    // asynchronous bodies.
    private func beginRun() {
        lock.lock()
        runCountValue += 1
        activeValue += 1
        maxActiveValue = max(maxActiveValue, activeValue)
        lock.unlock()
    }

    private func endRun() {
        lock.lock()
        activeValue -= 1
        lock.unlock()
    }

    private func noteMainThread(_ value: Bool) {
        lock.lock()
        ranOnMainThreadValue = value
        lock.unlock()
    }

    private func noteCancellation() {
        lock.lock()
        canceledRunCountValue += 1
        lock.unlock()
    }

    private func isReleased() -> Bool {
        lock.lock(); defer { lock.unlock() }; return releasedValue
    }

    private func currentThreadIsMain() -> Bool {
        Thread.isMainThread
    }

    private func waitOnGateBriefly() {
        _ = gate.wait(timeout: .now() + 0.01)
    }

    func statuses() async -> [AnalysisAgentStatus] {
        beginRun()
        noteMainThread(currentThreadIsMain())

        switch mode {
        case .immediate:
            break
        case .delayed(let seconds):
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        case .gated:
            // Deterministic hold: wake every 10ms to observe cancellation, or
            // leave as soon as the test releases the gate.
            while !isReleased() {
                if Task.isCancelled {
                    noteCancellation()
                    endRun()
                    return []
                }
                waitOnGateBriefly()
            }
        }

        if Task.isCancelled {
            noteCancellation()
            endRun()
            return []
        }
        endRun()
        return DiscoveryFixtureStatuses.readyPair()
    }
}

/// Synthetic statuses that stand in for installed agents. The paths are
/// fixture-only strings; no executable is invoked.
enum DiscoveryFixtureStatuses {
    static func readyPair() -> [AnalysisAgentStatus] {
        [
            AnalysisAgentStatus(
                kind: .codex,
                executableURL: URL(fileURLWithPath: "/tmp/reflect-fixture/codex"),
                availability: .ready
            ),
            AnalysisAgentStatus(
                kind: .claudeCode,
                executableURL: URL(fileURLWithPath: "/tmp/reflect-fixture/claude"),
                availability: .ready
            )
        ]
    }
}

struct SettingsDiscoveryTests {
    static let suiteName = "SettingsDiscoveryTests"

    /// Store pointed at a temporary directory with an injected fake provider.
    /// No real CLI can be reached through this path.
    @MainActor
    private func makeDiscoveryStore(
        provider: @escaping @Sendable () async -> [AnalysisAgentStatus]
    ) -> AppStore {
        AppStore(
            persistence: PersistenceController(directory: Fixtures.makeTempDirectory("settings-discovery")),
            secrets: MemorySecretStore(),
            home: Fixtures.makeTempDirectory("settings-discovery-home"),
            analysisAvailabilityProvider: provider
        )
    }

    /// Pumps the main run loop from the main thread so main-queue (main actor)
    /// work can progress while the test observes it, without arbitrary sleeps.
    @MainActor
    private func pumpMain(until condition: () -> Bool, timeout: TimeInterval = 10) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                throw TestFailure("timed out waiting for the expected store state")
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    // MARK: Off-main-actor execution

    /// The injected availability provider must execute away from the main
    /// actor even though the check is started from the main actor.
    @MainActor
    func injectedAvailabilityProviderRunsOffTheMainActor() throws {
        let probe = DiscoveryProbe()
        let store = makeDiscoveryStore(provider: {
            probe.recordSawMainThreadFromCurrentThread()
            return DiscoveryFixtureStatuses.readyPair()
        })

        store.refreshAnalysisAvailability()
        try pumpMain(until: { !store.isCheckingAnalysisAgents })

        try expectFalse(
            probe.sawMainThread,
            "injected agent discovery must not run on the main actor/main thread"
        )
        try expectEqual(store.analysisAgents.count, 2)
        try expectFalse(store.isCheckingAnalysisAgents)
        try expectTrue(store.analysisAgentsLastChecked != nil)
    }

    /// While a delayed discovery is pending, the main queue must keep
    /// servicing work: the provider enqueues a probe block on the main queue
    /// and sleeps away from it.
    @MainActor
    func mainQueueStaysResponsiveDuringDiscovery() throws {
        let probe = DiscoveryProbe()
        let provider = FakeDiscoveryProvider(mode: .delayed(0.25))
        let store = makeDiscoveryStore(provider: { await provider.statuses() })

        store.refreshAnalysisAvailability()
        try expectTrue(store.isCheckingAnalysisAgents, "the checking state must be visible immediately")

        DispatchQueue.main.async { probe.recordMainProbeRan() }
        try pumpMain(until: { !store.isCheckingAnalysisAgents })

        try expectTrue(
            probe.mainProbeRan,
            "the main queue must keep servicing work while agent discovery is pending"
        )
        try expectFalse(provider.ranOnMainThread, "delayed discovery must run off the main thread")
        try expectEqual(store.analysisAgents.count, 2)
    }

    // MARK: Appearance-driven single check

    @MainActor
    func firstAppearanceChecksOnceAndLaterAppearancesDoNotRepeatDiscovery() throws {
        let provider = FakeDiscoveryProvider(mode: .immediate)
        let store = makeDiscoveryStore(provider: { await provider.statuses() })

        store.ensureAnalysisAvailabilityChecked()
        try expectTrue(store.isCheckingAnalysisAgents)
        try pumpMain(until: { !store.isCheckingAnalysisAgents })
        try expectEqual(provider.runCount, 1)

        // Later appearances after a completed check never launch processes.
        store.ensureAnalysisAvailabilityChecked()
        store.ensureAnalysisAvailabilityChecked()
        try expectEqual(provider.runCount, 1)
        try expectEqual(store.analysisAgents.count, 2)
    }

    // MARK: Coalescing

    @MainActor
    func concurrentRefreshRequestsCoalesceAndNeverOverlap() throws {
        let provider = FakeDiscoveryProvider(mode: .delayed(0.2))
        let store = makeDiscoveryStore(provider: { await provider.statuses() })

        store.refreshAnalysisAvailability()
        // Overlapping explicit requests: at most one queued follow-up run.
        store.refreshAnalysisAvailability()
        store.refreshAnalysisAvailability()
        store.refreshAnalysisAvailability()
        // A pending check also absorbs appearance-driven requests.
        store.ensureAnalysisAvailabilityChecked()

        try pumpMain(until: { provider.runCount >= 2 && !store.isCheckingAnalysisAgents })

        try expectEqual(provider.runCount, 2, "overlapping requests collapse into the in-flight run plus one follow-up")
        try expectEqual(provider.maxConcurrentRuns, 1, "discovery runs must never overlap")
        try expectEqual(store.analysisAgents.count, 2)
        try expectFalse(store.isCheckingAnalysisAgents)
    }

    // MARK: Explicit refresh and retention

    @MainActor
    func explicitRefreshStartsNewCheckWhileLastResultStaysVisible() throws {
        let provider = FakeDiscoveryProvider(mode: .immediate)
        let store = makeDiscoveryStore(provider: { await provider.statuses() })

        store.refreshAnalysisAvailability()
        try pumpMain(until: { !store.isCheckingAnalysisAgents })
        let firstCheckedAt = try require(store.analysisAgentsLastChecked, "a completed check must record its time")
        try expectEqual(store.analysisAgents.count, 2)

        store.refreshAnalysisAvailability()
        try expectTrue(store.isCheckingAnalysisAgents, "an explicit refresh must start a new check")
        try expectEqual(store.analysisAgents.count, 2, "last-known statuses stay visible while refreshing")
        try expectEqual(store.analysisAgentsLastChecked, firstCheckedAt, "last-checked time stays visible while refreshing")

        try pumpMain(until: { !store.isCheckingAnalysisAgents })
        try expectEqual(provider.runCount, 2)
        let secondCheckedAt = try require(store.analysisAgentsLastChecked)
        try expectTrue(secondCheckedAt >= firstCheckedAt, "the new check records its own completion time")
        try expectEqual(store.analysisAgents.count, 2)
    }

    @MainActor
    func checkingStateIsVisibleBeforeAnyResultExists() throws {
        let provider = FakeDiscoveryProvider(mode: .gated)
        let store = makeDiscoveryStore(provider: { await provider.statuses() })

        store.ensureAnalysisAvailabilityChecked()
        try pumpMain(until: { provider.runCount == 1 })

        try expectTrue(store.isCheckingAnalysisAgents, "the UI must be able to show a checking state")
        try expectTrue(store.analysisAgents.isEmpty, "no result exists before the first check completes")
        try expectTrue(store.analysisAgentsLastChecked == nil, "no check time exists before the first completion")

        provider.release()
        try pumpMain(until: { !store.isCheckingAnalysisAgents })
        try expectEqual(store.analysisAgents.count, 2)
    }

    // MARK: Cancellation

    @MainActor
    func cancellationStopsFakeDiscoveryPublishesNoStaleResultAndLaterRefreshCompletes() throws {
        let provider = FakeDiscoveryProvider(mode: .gated)
        let store = makeDiscoveryStore(provider: { await provider.statuses() })

        store.ensureAnalysisAvailabilityChecked()
        try pumpMain(until: { provider.runCount == 1 })

        store.cancelAnalysisAvailabilityCheck()
        try pumpMain(until: { provider.canceledRunCount == 1 }, timeout: 5)

        try expectFalse(store.isCheckingAnalysisAgents, "a canceled check must leave the checking state")
        try expectTrue(store.analysisAgents.isEmpty, "a canceled check must not publish results")
        try expectTrue(store.analysisAgentsLastChecked == nil, "a canceled check must not record a check time")

        // A later explicit refresh still completes normally, uncanceled.
        store.refreshAnalysisAvailability()
        try pumpMain(until: { provider.runCount == 2 })
        provider.release()
        try pumpMain(until: { !store.isCheckingAnalysisAgents })

        try expectEqual(provider.runCount, 2, "the follow-up run must have started")
        try expectEqual(provider.canceledRunCount, 1, "exactly the canceled run observes cancellation")
        try expectEqual(store.analysisAgents.count, 2, "the later refresh publishes its result")
        try expectTrue(store.analysisAgentsLastChecked != nil)
    }

    // MARK: Real runner cancellation and timeout (synthetic /bin/sleep child)

    /// The real runner must stop waiting when the surrounding task is
    /// canceled: the child is terminated and CancellationError surfaces long
    /// before the invocation timeout would. The child is a synthetic system
    /// sleep process, never an agent CLI.
    func defaultRunnerCancellationStopsTheChildProcess() throws {
        let runner = DefaultAnalysisProcessRunner()
        let invocation = AnalysisProcessInvocation(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["5"],
            input: Data(),
            workingDirectory: Fixtures.makeTempDirectory("runner-cancel"),
            environment: [:],
            timeout: 30,
            outputLimit: 1024
        )

        let started = Date()
        let outcome = try Fixtures.awaitAsync { () -> String in
            let task = Task.detached(priority: .userInitiated) { try await runner.run(invocation) }
            try? await Task.sleep(nanoseconds: 300_000_000)
            task.cancel()
            do {
                _ = try await task.value
                return "completed"
            } catch is CancellationError {
                return "canceled"
            } catch {
                return "error"
            }
        }
        let elapsed = Date().timeIntervalSince(started)

        try expectEqual(outcome, "canceled", "cancellation must surface as CancellationError, not a result or timeout")
        try expectTrue(elapsed < 10, "cancellation must stop waiting well before the 30s timeout (took \(elapsed)s)")
    }

    /// The real runner keeps its bounded timeout on the async path: a hung
    /// child is terminated (and killed if needed) and the failure surfaces as
    /// a timeout, which discovery classifies as unknown.
    func defaultRunnerTimeoutTerminatesChildAndThrowsTimedOut() throws {
        let runner = DefaultAnalysisProcessRunner()
        let invocation = AnalysisProcessInvocation(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["5"],
            input: Data(),
            workingDirectory: Fixtures.makeTempDirectory("runner-timeout"),
            environment: [:],
            timeout: 0.5,
            outputLimit: 1024
        )

        let started = Date()
        let outcome = try Fixtures.awaitAsync { () -> String in
            do {
                _ = try await runner.run(invocation)
                return "completed"
            } catch is CancellationError {
                return "canceled"
            } catch let error as AnalysisProcessError {
                if case .timedOut = error { return "timedOut" }
                return "otherProcessError"
            } catch {
                return "error"
            }
        }
        let elapsed = Date().timeIntervalSince(started)

        try expectEqual(outcome, "timedOut", "a hung child must end in a bounded timeout")
        try expectTrue(elapsed < 10, "the timeout path must stay bounded (took \(elapsed)s)")
    }

    static var entries: [TestEntry] {
        let tests = SettingsDiscoveryTests()
        return [
            TestEntry(suite: suiteName, name: "injectedAvailabilityProviderRunsOffTheMainActor") {
                try MainActor.assumeIsolated { try tests.injectedAvailabilityProviderRunsOffTheMainActor() }
            },
            TestEntry(suite: suiteName, name: "mainQueueStaysResponsiveDuringDiscovery") {
                try MainActor.assumeIsolated { try tests.mainQueueStaysResponsiveDuringDiscovery() }
            },
            TestEntry(suite: suiteName, name: "firstAppearanceChecksOnceAndLaterAppearancesDoNotRepeatDiscovery") {
                try MainActor.assumeIsolated { try tests.firstAppearanceChecksOnceAndLaterAppearancesDoNotRepeatDiscovery() }
            },
            TestEntry(suite: suiteName, name: "concurrentRefreshRequestsCoalesceAndNeverOverlap") {
                try MainActor.assumeIsolated { try tests.concurrentRefreshRequestsCoalesceAndNeverOverlap() }
            },
            TestEntry(suite: suiteName, name: "explicitRefreshStartsNewCheckWhileLastResultStaysVisible") {
                try MainActor.assumeIsolated { try tests.explicitRefreshStartsNewCheckWhileLastResultStaysVisible() }
            },
            TestEntry(suite: suiteName, name: "checkingStateIsVisibleBeforeAnyResultExists") {
                try MainActor.assumeIsolated { try tests.checkingStateIsVisibleBeforeAnyResultExists() }
            },
            TestEntry(suite: suiteName, name: "cancellationStopsFakeDiscoveryPublishesNoStaleResultAndLaterRefreshCompletes") {
                try MainActor.assumeIsolated {
                    try tests.cancellationStopsFakeDiscoveryPublishesNoStaleResultAndLaterRefreshCompletes()
                }
            },
            TestEntry(suite: suiteName, name: "defaultRunnerCancellationStopsTheChildProcess") {
                try tests.defaultRunnerCancellationStopsTheChildProcess()
            },
            TestEntry(suite: suiteName, name: "defaultRunnerTimeoutTerminatesChildAndThrowsTimedOut") {
                try tests.defaultRunnerTimeoutTerminatesChildAndThrowsTimedOut()
            }
        ]
    }
}
