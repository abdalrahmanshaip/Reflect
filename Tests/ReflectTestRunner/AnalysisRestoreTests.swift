import Foundation
@testable import ReflectLib

/// Defect 2 regression coverage: a stored, attached analysis result must be
/// restored and displayed on reopening a day, without any Keychain or network
/// access, and the explicit selection/run gate stays intact.
struct AnalysisRestoreTests {
    static let suiteName = "AnalysisRestoreTests"
    private let dayKey = "2026-01-05"

    /// Records whether the runner is ever invoked (it must not be during restore).
    private final class ProbeBox {
        var runnerRuns = 0
    }

    @MainActor
    private func makeModel(_ probe: ProbeBox, status: AnalysisService.Status) -> OptionalAnalysisModel {
        OptionalAnalysisModel(
            statusProvider: { status },
            settingsProvider: { .default() },
            agentProvider: {
                AnalysisAgentStatus(
                    kind: .claudeCode,
                    executableURL: URL(fileURLWithPath: "/tmp/fixture/claude"),
                    availability: .ready
                )
            },
            runner: { _, _, _ in
                probe.runnerRuns += 1
                throw TestFailure("runner must never run during restore")
            }
        )
    }

    private func attachedReport(analysis: String?, at: Date?) -> DailyReport {
        DailyReport(
            day: dayKey,
            narrative: "",
            narrativeGeneratedAt: nil,
            answers: [:],
            analysisResult: analysis,
            analysisGeneratedAt: at,
            updatedAt: Fixtures.referenceDate
        )
    }

    // Reopening a day restores the saved attached result with its label inputs
    // (text + generation time) and without touching Keychain or network.
    @MainActor
    func storedAttachedAnalysisRestoresWithoutKeychainOrNetworkCalls() throws {
        let probe = ProbeBox()
        let model = makeModel(probe, status: .ready)
        let generatedAt = Fixtures.referenceDate
        let report = attachedReport(analysis: "Synthetic attached analysis from the explicit Run/Attach flow.", at: generatedAt)

        model.restoreAttached(from: report)

        guard case .restored(let text, let at) = model.runState else {
            throw TestFailure("expected .restored after opening a day with a stored result, got \(model.runState)")
        }
        try expectEqual(text, "Synthetic attached analysis from the explicit Run/Attach flow.")
        try expectEqual(try require(at), generatedAt, "the stored generation time must be restored for the label")
        try expectEqual(probe.runnerRuns, 0, "restoring must never call the provider")

        // The restored result does not loosen the explicit run gate: nothing is
        // selected, so nothing can run until the user explicitly selects again.
        try expectFalse(model.canRun, "no run may be possible without explicit selection")
        try expectEqual(model.selectionCount, 0)
    }

    // A stored result never blocks a fresh explicit run: after explicit
    // selection the run button becomes available, still without key reads.
    @MainActor
    func restoredStateKeepsExplicitRunGateUsable() throws {
        let probe = ProbeBox()
        let model = makeModel(probe, status: .ready)
        model.restoreAttached(from: attachedReport(analysis: "Synthetic earlier result.", at: Fixtures.referenceDate))
        try expectFalse(model.canRun)

        model.toggle("fixture-event-0")
        try expectTrue(model.canRun, "an explicit selection enables a fresh run")
    }

    // Days without a stored result stay idle; blank results never restore.
    @MainActor
    func restoreWithoutStoredAnalysisStaysIdle() throws {
        let probe = ProbeBox()
        let model = makeModel(probe, status: .disabled)
        model.restoreAttached(from: attachedReport(analysis: nil, at: nil))
        try expectEqual(model.runState, OptionalAnalysisModel.RunState.idle)

        model.restoreAttached(from: attachedReport(analysis: "   \n ", at: nil))
        try expectEqual(model.runState, OptionalAnalysisModel.RunState.idle,
                        "whitespace-only stored results must not render as restored")
    }

    // The explicit Attach flow persists the analysis fields, and a reopened
    // store over the same temporary directory still returns them.
    @MainActor
    func attachedAnalysisPersistsAcrossStoreReopen() throws {
        let directory = Fixtures.makeTempDirectory("analysis-restore-persist")
        let home = Fixtures.makeTempDirectory("analysis-restore-home")
        let store = AppStore(
            persistence: PersistenceController(directory: directory),
            secrets: MemorySecretStore(),
            home: home
        )
        var report = store.report(for: dayKey)
        report.answers["\(dayKey)-note"] = AnswerEntry(text: "Synthetic note kept separate.", updatedAt: Fixtures.referenceDate)
        let composer = ReflectionDraftModel(dayKey: dayKey, report: report, questions: []) { store.saveReport($0) }
        try expectTrue(composer.attachAnalysis("Synthetic labeled analysis output."), "explicit attach persists")

        // Reopen: a fresh store over the same directory (no in-memory state).
        let reopened = AppStore(
            persistence: PersistenceController(directory: directory),
            secrets: MemorySecretStore(),
            home: home
        )
        let restored = reopened.report(for: dayKey)
        try expectEqual(restored.analysisResult, "Synthetic labeled analysis output.")
        try expectTrue(restored.analysisGeneratedAt != nil, "the generation timestamp persists")
        try expectEqual(restored.answers["\(dayKey)-note"]?.text, "Synthetic note kept separate.",
                        "user answers persist separately from the attached analysis")

        let probe = ProbeBox()
        let model = makeModel(probe, status: .disabled)
        model.restoreAttached(from: restored)
        guard case .restored = model.runState else {
            throw TestFailure("reopening the day must surface the persisted result, got \(model.runState)")
        }
    }

    static var entries: [TestEntry] {
        let tests = AnalysisRestoreTests()
        return [
            TestEntry(suite: suiteName, name: "storedAttachedAnalysisRestoresWithoutKeychainOrNetworkCalls") {
                try MainActor.assumeIsolated { try tests.storedAttachedAnalysisRestoresWithoutKeychainOrNetworkCalls() }
            },
            TestEntry(suite: suiteName, name: "restoredStateKeepsExplicitRunGateUsable") {
                try MainActor.assumeIsolated { try tests.restoredStateKeepsExplicitRunGateUsable() }
            },
            TestEntry(suite: suiteName, name: "restoreWithoutStoredAnalysisStaysIdle") {
                try MainActor.assumeIsolated { try tests.restoreWithoutStoredAnalysisStaysIdle() }
            },
            TestEntry(suite: suiteName, name: "attachedAnalysisPersistsAcrossStoreReopen") {
                try MainActor.assumeIsolated { try tests.attachedAnalysisPersistsAcrossStoreReopen() }
            }
        ]
    }
}
