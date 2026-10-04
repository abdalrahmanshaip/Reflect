import Foundation
@testable import ReflectLib

private final class RecordingAnalysisRunner: AnalysisProcessRunning {
    var invocations: [AnalysisProcessInvocation] = []
    var result = AnalysisProcessResult(stdout: Data("Synthetic analysis output.".utf8), stderr: Data(), terminationStatus: 0)

    func run(_ invocation: AnalysisProcessInvocation) throws -> AnalysisProcessResult {
        invocations.append(invocation)
        return result
    }
}

struct AnalysisServiceTests {
    static let suiteName = "AnalysisServiceTests"

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

    private func correction(_ eventId: String, _ attribution: Attribution) -> AttributionCorrection {
        AttributionCorrection(eventId: eventId, attribution: attribution, updatedAt: Fixtures.referenceDate)
    }

    func statusIsDisabledByDefault() throws {
        try expectEqual(AnalysisService.status(settings: AppSettings(), agentAvailable: true), .disabled)
    }

    func statusRequiresSelectedReadyAgent() throws {
        var settings = AppSettings()
        settings.aiEnabled = true
        try expectTrue(isIncomplete(AnalysisService.status(settings: settings, agentAvailable: true)))

        settings.analysisAgent = .claudeCode
        try expectTrue(isIncomplete(AnalysisService.status(settings: settings, agentAvailable: false)))
        try expectEqual(AnalysisService.status(settings: settings, agentAvailable: true), .ready)
    }

    func buildInputSendsOnlySelectedEvents() throws {
        let events = Fixtures.dayEvents(count: 2)
        let input = String(decoding: AnalysisService.buildInput(events: events, maxPreviewCharacters: 120), as: UTF8.self)

        try expectTrue(input.contains(events[0].id))
        try expectTrue(input.contains(events[1].id))
        try expectTrue(input.contains(events[0].sourceName))
        try expectFalse(input.contains("fixture-event-9"), "unselected events must not be sent")
    }

    // M0 Task D: corrections are serialized as their own labeled section for
    // selected records only, while each record keeps its observed attribution
    // exactly as recorded.
    func buildInputLabelsCorrectionsSeparatelyForSelectedRecordsOnly() throws {
        let events = Fixtures.dayEvents(count: 2)
        let input = String(decoding: AnalysisService.buildInput(
            events: events,
            maxPreviewCharacters: 120,
            corrections: [
                correction(events[1].id, .you),
                correction("fixture-event-9", .agent)
            ]
        ), as: UTF8.self)

        try expectTrue(input.contains("User attribution corrections"),
                       "corrections carry their own labeled section: \(input)")
        try expectTrue(input.contains("your correction=You"),
                       "the selected record's correction is serialized: \(input)")
        try expectTrue(input.contains("observed=\(events[1].observedAttribution.label)"),
                       "the observed attribution of the corrected record is retained unchanged: \(input)")
        try expectFalse(input.contains("fixture-event-9"),
                        "corrections for unselected records must never be serialized: \(input)")
        try expectFalse(input.contains("your correction=Agent"),
                        "only the selected record's correction is serialized: \(input)")
    }

    func buildInputWithoutCorrectionsOmitsCorrectionSection() throws {
        let events = Fixtures.dayEvents(count: 1)
        let input = String(decoding: AnalysisService.buildInput(events: events, maxPreviewCharacters: 120), as: UTF8.self)
        try expectFalse(input.contains("User attribution corrections"),
                        "no correction section is sent when nothing was corrected: \(input)")
    }

    func runTransmitsCorrectionsForSelectedRecordsOnly() throws {
        let recording = RecordingAnalysisRunner()
        let events = Fixtures.dayEvents(count: 2)
        _ = try AnalysisService().run(
            selectedEvents: [events[0]],
            settings: readySettings(),
            agent: agent,
            corrections: [correction(events[0].id, .you), correction(events[1].id, .agent)],
            processRunner: recording,
            temporaryDirectory: Fixtures.makeTempDirectory("analysis-corrections-run")
        )
        try expectEqual(recording.invocations.count, 1)
        let input = String(decoding: recording.invocations[0].input, as: UTF8.self)
        try expectTrue(input.contains("your correction=You"),
                       "the selected record's correction reaches the payload: \(input)")
        try expectFalse(input.contains(events[1].id),
                        "unselected records and their corrections must not be sent: \(input)")
    }

    func noProcessWhenOpeningOrSelecting() throws {
        let recording = RecordingAnalysisRunner()
        try MainActor.assumeIsolated {
            let model = OptionalAnalysisModel(
                statusProvider: { .ready },
                settingsProvider: { self.readySettings() },
                agentProvider: { self.agent },
                runner: { events, settings, agent in
                    try AnalysisService().run(
                        selectedEvents: events,
                        settings: settings,
                        agent: agent,
                        processRunner: recording,
                        temporaryDirectory: Fixtures.makeTempDirectory("analysis-model-open")
                    )
                }
            )

            try expectTrue(recording.invocations.isEmpty, "opening starts no agent process")
            let events = Fixtures.dayEvents(count: 4)
            events.forEach { model.toggle($0.id) }
            model.setPage(1, pageCount: 3)
            model.setPage(0, pageCount: 3)
            try expectTrue(recording.invocations.isEmpty, "selection and paging start no agent process")
        }
    }

    func runIsGatedByReadyStatusAndSelection() throws {
        try MainActor.assumeIsolated {
            var status: AnalysisService.Status = .disabled
            let model = OptionalAnalysisModel(
                statusProvider: { status },
                settingsProvider: { self.readySettings() },
                agentProvider: { self.agent },
                runner: { _, _, _ in
                    throw AnalysisService.AnalysisError.emptyOutput
                }
            )

            try expectFalse(model.canRun)
            model.toggle("fixture-event-0")
            try expectFalse(model.canRun)
            status = .ready
            model.clearSelection()
            try expectFalse(model.canRun)
            model.toggle("fixture-event-1")
            try expectTrue(model.canRun)
        }
    }

    func explicitRunUsesFakeProcessAndOnlySelectedEvents() throws {
        let recording = RecordingAnalysisRunner()
        try MainActor.assumeIsolated {
            let model = OptionalAnalysisModel(
                statusProvider: { .ready },
                settingsProvider: { self.readySettings() },
                agentProvider: { self.agent },
                runner: { events, settings, agent in
                    try AnalysisService().run(
                        selectedEvents: events,
                        settings: settings,
                        agent: agent,
                        processRunner: recording,
                        temporaryDirectory: Fixtures.makeTempDirectory("analysis-model-run")
                    )
                }
            )
            let all = Fixtures.dayEvents(count: 5)
            model.toggle(all[1].id)
            model.toggle(all[3].id)

            let flag = RunLoopFlag()
            Task {
                let selected = all.filter { model.selectedEventIDs.contains($0.id) }
                await model.run(selectedEvents: selected)
                flag.finish()
            }
            while !flag.isDone {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }

            try expectEqual(recording.invocations.count, 1)
            let input = String(decoding: recording.invocations[0].input, as: UTF8.self)
            try expectTrue(input.contains(all[1].id) && input.contains(all[3].id))
            try expectFalse(input.contains(all[0].id), "unselected events must not be sent")
            try expectFalse(input.contains(all[4].id), "unselected events must not be sent")
            guard case .finished(let text, let info) = model.runState else {
                throw TestFailure("expected a finished synthetic run")
            }
            try expectEqual(text, "Synthetic analysis output.")
            try expectTrue(info.contains("Claude Code"))
        }
    }

    // M0 Task D: the model's Run wires the separately persisted corrections
    // into the service, which scopes them to the selected records. This
    // mirrors the TodayView runner composition with a fake process runner.
    @MainActor
    func modelRunWiresCorrectionsIntoServicePayload() throws {
        let recording = RecordingAnalysisRunner()
        let events = Fixtures.dayEvents(count: 3)
        let storedCorrections = [
            correction(events[1].id, .you),
            correction(events[2].id, .agent)
        ]
        let model = OptionalAnalysisModel(
            statusProvider: { .ready },
            settingsProvider: { self.readySettings() },
            agentProvider: { self.agent },
            runner: { selected, settings, agent in
                try AnalysisService().run(
                    selectedEvents: selected,
                    settings: settings,
                    agent: agent,
                    corrections: storedCorrections,
                    processRunner: recording,
                    temporaryDirectory: Fixtures.makeTempDirectory("analysis-model-corrections")
                )
            }
        )
        model.toggle(events[1].id)

        let flag = RunLoopFlag()
        Task {
            let selected = events.filter { model.selectedEventIDs.contains($0.id) }
            await model.run(selectedEvents: selected)
            flag.finish()
        }
        while !flag.isDone {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }

        try expectEqual(recording.invocations.count, 1)
        let input = String(decoding: recording.invocations[0].input, as: UTF8.self)
        try expectTrue(input.contains("your correction=You"),
                       "the selected record's correction is sent: \(input)")
        try expectFalse(input.contains(events[2].id),
                        "the unselected record and its correction stay local: \(input)")
        guard case .finished = model.runState else {
            throw TestFailure("expected a finished synthetic run, got \(model.runState)")
        }
    }

    private func isIncomplete(_ status: AnalysisService.Status) -> Bool {
        if case .incomplete = status { return true }
        return false
    }

    static var entries: [TestEntry] {
        let tests = AnalysisServiceTests()
        return [
            TestEntry(suite: suiteName, name: "statusIsDisabledByDefault") { try tests.statusIsDisabledByDefault() },
            TestEntry(suite: suiteName, name: "statusRequiresSelectedReadyAgent") { try tests.statusRequiresSelectedReadyAgent() },
            TestEntry(suite: suiteName, name: "buildInputSendsOnlySelectedEvents") { try tests.buildInputSendsOnlySelectedEvents() },
            TestEntry(suite: suiteName, name: "buildInputLabelsCorrectionsSeparatelyForSelectedRecordsOnly") {
                try tests.buildInputLabelsCorrectionsSeparatelyForSelectedRecordsOnly()
            },
            TestEntry(suite: suiteName, name: "buildInputWithoutCorrectionsOmitsCorrectionSection") {
                try tests.buildInputWithoutCorrectionsOmitsCorrectionSection()
            },
            TestEntry(suite: suiteName, name: "runTransmitsCorrectionsForSelectedRecordsOnly") {
                try tests.runTransmitsCorrectionsForSelectedRecordsOnly()
            },
            TestEntry(suite: suiteName, name: "noProcessWhenOpeningOrSelecting") { try tests.noProcessWhenOpeningOrSelecting() },
            TestEntry(suite: suiteName, name: "runIsGatedByReadyStatusAndSelection") { try tests.runIsGatedByReadyStatusAndSelection() },
            TestEntry(suite: suiteName, name: "explicitRunUsesFakeProcessAndOnlySelectedEvents") {
                try tests.explicitRunUsesFakeProcessAndOnlySelectedEvents()
            },
            TestEntry(suite: suiteName, name: "modelRunWiresCorrectionsIntoServicePayload") {
                try MainActor.assumeIsolated { try tests.modelRunWiresCorrectionsIntoServicePayload() }
            }
        ]
    }
}

final class RunLoopFlag {
    private(set) var isDone = false
    func finish() { isDone = true }
}
