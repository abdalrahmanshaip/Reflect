import Foundation
@testable import ReflectLib

/// M0 Task D regression coverage: the analysis panel's visible status must be
/// truthful about what the explicit Run actually did. A completed run sent the
/// selected records to the agent's service, so the status can no longer claim
/// "Nothing has been sent yet".
struct AnalysisStatusHonestyTests {
    static let suiteName = "AnalysisStatusHonestyTests"

    private let agent = AnalysisAgentStatus(
        kind: .claudeCode,
        executableURL: URL(fileURLWithPath: "/tmp/fixture/claude"),
        availability: .ready
    )

    private func readySettings() -> AppSettings {
        var settings = AppSettings()
        settings.aiEnabled = true
        settings.analysisAgent = .claudeCode
        settings.setModel("sonnet", for: .claudeCode)
        return settings
    }

    private func syntheticResult() -> AnalysisResult {
        AnalysisResult(
            text: "Synthetic analysis output.",
            inputTokens: nil,
            outputTokens: nil,
            estimatedCostUSD: nil,
            model: "sonnet",
            endpoint: "",
            usedRequestedUsage: false,
            agent: .claudeCode
        )
    }

    // After a completed run the status must report that the selected records
    // were sent, never "Nothing has been sent yet".
    @MainActor
    func completedRunStatusDoesNotClaimNothingWasSent() throws {
        let model = OptionalAnalysisModel(
            statusProvider: { .ready },
            settingsProvider: { self.readySettings() },
            agentProvider: { self.agent },
            runner: { _, _, _ in self.syntheticResult() }
        )
        model.toggle("fixture-event-0")
        let flag = RunLoopFlag()
        Task {
            await model.run(selectedEvents: Fixtures.dayEvents(count: 1))
            flag.finish()
        }
        while !flag.isDone {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        guard case .finished = model.runState else {
            throw TestFailure("expected a finished synthetic run, got \(model.runState)")
        }
        try expectFalse(
            model.statusText.lowercased().contains("nothing has been sent"),
            "a completed run sent the selected records; the status must not claim otherwise: \(model.statusText)"
        )
        try expectTrue(
            model.statusText.lowercased().contains("sent"),
            "the completed status must say the records were sent: \(model.statusText)"
        )
    }

    // Before any run, the status must not make an absolute "nothing has been
    // sent" claim (an earlier unattached run cannot be ruled out); it names
    // the explicit run as the only send trigger instead.
    @MainActor
    func readyIdleStatusNamesExplicitRunAsOnlySendTrigger() throws {
        let model = OptionalAnalysisModel(
            statusProvider: { .ready },
            settingsProvider: { self.readySettings() },
            agentProvider: { self.agent },
            runner: { _, _, _ in throw TestFailure("no run happens in this test") }
        )
        try expectEqual(model.runState, OptionalAnalysisModel.RunState.idle)
        let status = model.statusText.lowercased()
        try expectTrue(status.contains("explicitly run"),
                       "the idle status names the explicit run as the send trigger: \(model.statusText)")
        try expectFalse(status.contains("nothing has been sent"),
                        "an idle view cannot prove no earlier run occurred: \(model.statusText)")
    }

    // The in-flight copy must name the sending in progress. The fake runner
    // waits on an in-process flag — a pure gate with no subprocess involved.
    @MainActor
    func runningStatusNamesTheInFlightSend() throws {
        var release = false
        let model = OptionalAnalysisModel(
            statusProvider: { .ready },
            settingsProvider: { self.readySettings() },
            agentProvider: { self.agent },
            runner: { _, _, _ in
                while !release {
                    try? await Task.sleep(nanoseconds: 5_000_000)
                }
                return self.syntheticResult()
            }
        )
        model.toggle("fixture-event-0")
        let flag = RunLoopFlag()
        Task {
            await model.run(selectedEvents: Fixtures.dayEvents(count: 1))
            flag.finish()
        }
        let inFlightDeadline = Date().addingTimeInterval(10)
        while !model.isRunInFlight && !flag.isDone && Date() < inFlightDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        try expectTrue(model.isRunInFlight, "the gated run should be observable while in flight")
        let status = model.statusText.lowercased()
        try expectTrue(status.contains("sending"),
                       "the in-flight status names the ongoing send: \(model.statusText)")
        try expectFalse(status.contains("nothing has been sent"),
                        "a run in flight falsifies the old idle claim: \(model.statusText)")
        release = true
        let finishDeadline = Date().addingTimeInterval(10)
        while !flag.isDone && Date() < finishDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        guard case .finished = model.runState else {
            throw TestFailure("expected the gated run to finish, got \(model.runState)")
        }
    }

    // An ordinary failure (not cancellation) lands in the distinct failed
    // state, and its copy states the outcome as unknown without ever naming a
    // cancellation.
    @MainActor
    func failedRunStatusReportsUnknownOutcomeInsteadOfNothingSent() throws {
        let model = OptionalAnalysisModel(
            statusProvider: { .ready },
            settingsProvider: { self.readySettings() },
            agentProvider: { self.agent },
            runner: { _, _, _ in throw AnalysisService.AnalysisError.emptyOutput }
        )
        model.toggle("fixture-event-0")
        let flag = RunLoopFlag()
        Task {
            await model.run(selectedEvents: Fixtures.dayEvents(count: 1))
            flag.finish()
        }
        while !flag.isDone {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        guard case .failed = model.runState else {
            throw TestFailure("expected an ordinary failure to land in failed state, got \(model.runState)")
        }
        try expectNotEqual(model.runState, OptionalAnalysisModel.RunState.cancelled,
                           "an ordinary failure must stay distinct from cancellation")
        let status = model.statusText.lowercased()
        try expectTrue(status.contains("unknown"),
                       "a failed attempt must report the outcome as unknown: \(model.statusText)")
        try expectFalse(status.contains("cancel"),
                        "the failed copy must stay distinct from the canceled copy: \(model.statusText)")
        try expectFalse(status.contains("nothing has been sent"),
                        "a failed attempt must not claim nothing was sent: \(model.statusText)")
        try expectFalse(status.contains("were sent"),
                        "a failed attempt must not claim records were (successfully) sent: \(model.statusText)")
    }

    // A run that stops through a thrown CancellationError lands in the
    // distinct cancelled state, whose copy states that some or all selected
    // records may already have been sent and that the transmission outcome is
    // unknown. This pins state handling and copy only — it is NOT proof of
    // live subprocess cancellation, which the synchronous analysis runner does
    // not offer (and no Cancel button is added).
    @MainActor
    func cancelledRunLandsInDistinctStateWithUnknownOutcomeCopy() throws {
        let model = OptionalAnalysisModel(
            statusProvider: { .ready },
            settingsProvider: { self.readySettings() },
            agentProvider: { self.agent },
            runner: { _, _, _ in throw CancellationError() }
        )
        model.toggle("fixture-event-0")
        let flag = RunLoopFlag()
        Task {
            await model.run(selectedEvents: Fixtures.dayEvents(count: 1))
            flag.finish()
        }
        while !flag.isDone {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        try expectEqual(model.runState, OptionalAnalysisModel.RunState.cancelled,
                        "a thrown CancellationError must land in the distinct cancelled state")
        let status = model.statusText.lowercased()
        try expectTrue(status.contains("cancel"),
                       "the canceled copy names the cancellation: \(model.statusText)")
        try expectTrue(status.contains("unknown"),
                       "the canceled copy states the transmission outcome as unknown: \(model.statusText)")
        try expectTrue(status.contains("already have been sent"),
                       "the canceled copy says some or all records may already have been sent: \(model.statusText)")
        try expectFalse(status.contains("nothing has been sent"),
                        "a canceled run must not claim nothing was sent: \(model.statusText)")
        try expectFalse(status.contains("were sent"),
                        "a canceled run must not claim records were (successfully) sent: \(model.statusText)")
    }

    // A restored result is storage from an earlier run: the status must show
    // the original run date and must not imply a new invocation.
    @MainActor
    func restoredStatusShowsOriginalRunDateAndDoesNotClaimNewAnalysis() throws {
        let model = OptionalAnalysisModel(
            statusProvider: { .ready },
            settingsProvider: { self.readySettings() },
            agentProvider: { self.agent },
            runner: { _, _, _ in throw TestFailure("restoring must never invoke the runner") }
        )
        let generatedAt = Fixtures.referenceDate
        model.restoreAttached(from: attachedReport(analysis: "Synthetic earlier result.", at: generatedAt))
        guard case .restored = model.runState else {
            throw TestFailure("expected restored state, got \(model.runState)")
        }
        let status = model.statusText
        try expectTrue(status.contains(Fmt.dateTime(generatedAt)),
                       "the restored status shows the original run date: \(status)")
        try expectTrue(status.lowercased().contains("earlier run"),
                       "the restored status attributes the result to an earlier run: \(status)")
        try expectFalse(status.lowercased().contains("nothing has been sent"),
                        "a restored result proves an earlier run sent records: \(status)")
        try expectFalse(status.lowercased().contains("no analysis has run"),
                        "a restored day cannot claim no analysis has run: \(status)")
    }

    // A restored attached result stays visible when AI later becomes disabled:
    // the original run date and the earlier-run attribution must not be hidden
    // by the availability copy, which is appended instead.
    @MainActor
    func restoredResultStaysVisibleWhenAIBecomesDisabled() throws {
        var status: AnalysisService.Status = .ready
        let model = OptionalAnalysisModel(
            statusProvider: { status },
            settingsProvider: { self.readySettings() },
            agentProvider: { self.agent },
            runner: { _, _, _ in throw TestFailure("restoring must never invoke the runner") }
        )
        let generatedAt = Fixtures.referenceDate
        model.restoreAttached(from: attachedReport(analysis: "Synthetic earlier result.", at: generatedAt))

        let readyStatus = model.statusText
        try expectTrue(readyStatus.contains(Fmt.dateTime(generatedAt)), "the run date is visible while ready: \(readyStatus)")

        status = .disabled
        let disabledStatus = model.statusText
        try expectTrue(disabledStatus.contains(Fmt.dateTime(generatedAt)),
                       "the original run date stays visible after AI is disabled: \(disabledStatus)")
        try expectTrue(disabledStatus.lowercased().contains("earlier run"),
                       "the earlier-run attribution stays visible after AI is disabled: \(disabledStatus)")
        try expectTrue(disabledStatus.lowercased().contains("no new analysis"),
                       "the no-new-invocation statement stays visible after AI is disabled: \(disabledStatus)")
        try expectTrue(disabledStatus.contains("disabled"),
                       "the current availability information is appended: \(disabledStatus)")
        try expectFalse(disabledStatus == "AI analysis is disabled (default). No network calls are made. Enable and configure it in Settings.",
                        "the availability copy alone must not replace the operation history: \(disabledStatus)")
    }

    // A completed run's sent-history stays visible when AI later becomes
    // disabled, with the disabled copy appended rather than replacing it.
    @MainActor
    func completedRunStaysVisibleWhenAIBecomesDisabled() throws {
        var status: AnalysisService.Status = .ready
        let model = OptionalAnalysisModel(
            statusProvider: { status },
            settingsProvider: { self.readySettings() },
            agentProvider: { self.agent },
            runner: { _, _, _ in self.syntheticResult() }
        )
        model.toggle("fixture-event-0")
        let flag = RunLoopFlag()
        Task {
            await model.run(selectedEvents: Fixtures.dayEvents(count: 1))
            flag.finish()
        }
        while !flag.isDone {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        guard case .finished = model.runState else {
            throw TestFailure("expected a finished synthetic run, got \(model.runState)")
        }

        status = .disabled
        let disabledStatus = model.statusText
        try expectTrue(disabledStatus.lowercased().contains("were sent"),
                       "the sent history stays visible after AI is disabled: \(disabledStatus)")
        try expectFalse(disabledStatus.lowercased().contains("nothing has been sent"),
                        "the disabled copy must not resurrect the idle claim: \(disabledStatus)")
        try expectTrue(disabledStatus.contains("disabled"),
                       "the current availability information is appended: \(disabledStatus)")
    }

    // A canceled run's unknown-outcome copy stays visible when AI later
    // becomes disabled. State handling only — not live cancellation proof.
    @MainActor
    func cancelledRunOutcomeStaysVisibleWhenAIBecomesDisabled() throws {
        var status: AnalysisService.Status = .ready
        let model = OptionalAnalysisModel(
            statusProvider: { status },
            settingsProvider: { self.readySettings() },
            agentProvider: { self.agent },
            runner: { _, _, _ in throw CancellationError() }
        )
        model.toggle("fixture-event-0")
        let flag = RunLoopFlag()
        Task {
            await model.run(selectedEvents: Fixtures.dayEvents(count: 1))
            flag.finish()
        }
        while !flag.isDone {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        try expectEqual(model.runState, OptionalAnalysisModel.RunState.cancelled)

        status = .disabled
        let disabledStatus = model.statusText
        try expectTrue(disabledStatus.lowercased().contains("cancel"),
                       "the cancellation stays visible after AI is disabled: \(disabledStatus)")
        try expectTrue(disabledStatus.lowercased().contains("unknown"),
                       "the unknown transmission outcome stays visible after AI is disabled: \(disabledStatus)")
        try expectTrue(disabledStatus.lowercased().contains("already have been sent"),
                       "the may-already-have-been-sent statement stays visible: \(disabledStatus)")
        try expectTrue(disabledStatus.contains("disabled"),
                       "the current availability information is appended: \(disabledStatus)")
    }

    // The normal disabled-idle state keeps its availability-only copy: it
    // makes no operation-history claims in either direction.
    @MainActor
    func disabledIdleStatusMakesNoOperationHistoryClaims() throws {
        let model = OptionalAnalysisModel(
            statusProvider: { .disabled },
            settingsProvider: { self.readySettings() },
            agentProvider: { self.agent },
            runner: { _, _, _ in throw TestFailure("no run may happen while disabled") }
        )
        try expectEqual(model.runState, OptionalAnalysisModel.RunState.idle)
        let status = model.statusText
        try expectTrue(status.contains("disabled (default)") && status.contains("No network calls are made"),
                       "the disabled idle copy states current availability: \(status)")
        try expectFalse(status.lowercased().contains("were sent"),
                        "the idle copy must not claim records were sent: \(status)")
        try expectFalse(status.lowercased().contains("nothing has been sent"),
                        "the idle copy must not make the absolute nothing-sent claim: \(status)")
        try expectFalse(status.lowercased().contains("earlier run"),
                        "the idle copy must not invent operation history: \(status)")
    }

    // Parent status derivation: the privacy line's send state is derived from
    // storage plus the model's published run state, so a finished run flips a
    // not-sent day to sent and a failed attempt reports the unknown outcome.
    func sendStateDerivationCoversStorageAndRunStates() throws {
        try expectEqual(AnalysisPrivacyNote.sendState(hasStoredAnalysis: false, runState: nil), .noAttachedResult)
        try expectEqual(AnalysisPrivacyNote.sendState(hasStoredAnalysis: true, runState: nil), .sent)
        try expectEqual(AnalysisPrivacyNote.sendState(hasStoredAnalysis: false, runState: .idle), .noAttachedResult)
        try expectEqual(AnalysisPrivacyNote.sendState(hasStoredAnalysis: true, runState: .idle), .sent)
        try expectEqual(AnalysisPrivacyNote.sendState(hasStoredAnalysis: true, runState: .running), .inFlight)
        try expectEqual(AnalysisPrivacyNote.sendState(hasStoredAnalysis: false, runState: .running), .inFlight)
        try expectEqual(
            AnalysisPrivacyNote.sendState(hasStoredAnalysis: false, runState: .finished(text: "t", info: "i")),
            .sent
        )
        try expectEqual(AnalysisPrivacyNote.sendState(hasStoredAnalysis: false, runState: .failed("x")), .attemptFailed)
        try expectEqual(
            AnalysisPrivacyNote.sendState(hasStoredAnalysis: true, runState: .failed("x")),
            .sent,
            "a stored attached result still proves an earlier send after a later failed attempt"
        )
        try expectEqual(AnalysisPrivacyNote.sendState(hasStoredAnalysis: false, runState: .cancelled), .attemptFailed,
                        "a canceled run is an incomplete attempt with unknown transmission")
        try expectEqual(
            AnalysisPrivacyNote.sendState(hasStoredAnalysis: true, runState: .cancelled),
            .sent,
            "a stored attached result still proves an earlier send after a later canceled run"
        )
        try expectNotEqual(
            AnalysisPrivacyNote.sendState(hasStoredAnalysis: false, runState: .cancelled),
            AnalysisPrivacyNote.sendState(hasStoredAnalysis: false, runState: .finished(text: "t", info: "i")),
            "cancellation must not map to the sent state"
        )
        try expectEqual(
            AnalysisPrivacyNote.sendState(hasStoredAnalysis: true, runState: .restored(text: "t", generatedAt: nil)),
            .sent
        )
    }

    // The failed-attempt wording the parent derivation feeds must stay honest
    // about the unknown transmission outcome.
    func failedSendStateTextReportsUnknownOutcome() throws {
        let note = AnalysisPrivacyNote.text(
            aiEnabled: true,
            state: AnalysisPrivacyNote.sendState(hasStoredAnalysis: false, runState: .failed("simulated"))
        )
        try expectTrue(note.lowercased().contains("unknown"),
                       "the derived failed note reports the outcome as unknown: \(note)")
        try expectFalse(note.contains("Nothing from this day has left this Mac"),
                        "the derived failed note never claims nothing left the Mac: \(note)")
    }

    private func attachedReport(analysis: String, at: Date?) -> DailyReport {
        DailyReport(
            day: "2026-01-05",
            narrative: "",
            narrativeGeneratedAt: nil,
            answers: [:],
            analysisResult: analysis,
            analysisGeneratedAt: at,
            updatedAt: Fixtures.referenceDate
        )
    }

    static var entries: [TestEntry] {
        let tests = AnalysisStatusHonestyTests()
        return [
            TestEntry(suite: suiteName, name: "completedRunStatusDoesNotClaimNothingWasSent") {
                try MainActor.assumeIsolated { try tests.completedRunStatusDoesNotClaimNothingWasSent() }
            },
            TestEntry(suite: suiteName, name: "readyIdleStatusNamesExplicitRunAsOnlySendTrigger") {
                try MainActor.assumeIsolated { try tests.readyIdleStatusNamesExplicitRunAsOnlySendTrigger() }
            },
            TestEntry(suite: suiteName, name: "runningStatusNamesTheInFlightSend") {
                try MainActor.assumeIsolated { try tests.runningStatusNamesTheInFlightSend() }
            },
            TestEntry(suite: suiteName, name: "failedRunStatusReportsUnknownOutcomeInsteadOfNothingSent") {
                try MainActor.assumeIsolated { try tests.failedRunStatusReportsUnknownOutcomeInsteadOfNothingSent() }
            },
            TestEntry(suite: suiteName, name: "cancelledRunLandsInDistinctStateWithUnknownOutcomeCopy") {
                try MainActor.assumeIsolated { try tests.cancelledRunLandsInDistinctStateWithUnknownOutcomeCopy() }
            },
            TestEntry(suite: suiteName, name: "restoredStatusShowsOriginalRunDateAndDoesNotClaimNewAnalysis") {
                try MainActor.assumeIsolated { try tests.restoredStatusShowsOriginalRunDateAndDoesNotClaimNewAnalysis() }
            },
            TestEntry(suite: suiteName, name: "restoredResultStaysVisibleWhenAIBecomesDisabled") {
                try MainActor.assumeIsolated { try tests.restoredResultStaysVisibleWhenAIBecomesDisabled() }
            },
            TestEntry(suite: suiteName, name: "completedRunStaysVisibleWhenAIBecomesDisabled") {
                try MainActor.assumeIsolated { try tests.completedRunStaysVisibleWhenAIBecomesDisabled() }
            },
            TestEntry(suite: suiteName, name: "cancelledRunOutcomeStaysVisibleWhenAIBecomesDisabled") {
                try MainActor.assumeIsolated { try tests.cancelledRunOutcomeStaysVisibleWhenAIBecomesDisabled() }
            },
            TestEntry(suite: suiteName, name: "disabledIdleStatusMakesNoOperationHistoryClaims") {
                try MainActor.assumeIsolated { try tests.disabledIdleStatusMakesNoOperationHistoryClaims() }
            },
            TestEntry(suite: suiteName, name: "sendStateDerivationCoversStorageAndRunStates") {
                try tests.sendStateDerivationCoversStorageAndRunStates()
            },
            TestEntry(suite: suiteName, name: "failedSendStateTextReportsUnknownOutcome") {
                try tests.failedSendStateTextReportsUnknownOutcome()
            }
        ]
    }
}
