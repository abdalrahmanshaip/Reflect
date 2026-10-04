import Foundation
@testable import ReflectLib

/// Synthetic settings/status matrix for the conversation runtime resolver.
/// Fake executable paths are constructed URLs only; nothing is executed or read.
struct ConversationRuntimeConfigurationTests {
    static let suiteName = "ConversationRuntimeConfigurationTests"

    private let fakeCodexURL = URL(fileURLWithPath: "/tmp/fixture/codex")
    private let fakeClaudeURL = URL(fileURLWithPath: "/tmp/fixture/claude")

    private func readyStatus(_ kind: AnalysisAgentKind, url: URL?) -> AnalysisAgentStatus {
        AnalysisAgentStatus(kind: kind, executableURL: url, availability: .ready)
    }

    func initialStateIsDisabledWithoutAgentOrPath() throws {
        let runtime = ConversationRuntimeConfiguration()

        let configuration = runtime.currentConfiguration()
        let snapshot = runtime.currentSnapshot()

        guard case .disabled = configuration.state else {
            throw TestFailure("expected initial state disabled, got \(configuration.state)")
        }
        try expectNil(configuration.agentKind, "initial state must not imply an agent")
        try expectNil(configuration.selectedModel, "initial state must not imply a model")
        try expectNil(snapshot.executableURL, "initial state must not carry an executable path")
    }

    func turnedOffSettingsYieldDisabledAndClearPath() throws {
        var settings = AppSettings()
        settings.aiEnabled = true
        settings.analysisAgent = .codex

        let runtime = ConversationRuntimeConfiguration()
        runtime.update(settings: settings, agentStatuses: [readyStatus(.codex, url: fakeCodexURL)])
        try expectTrue(runtime.currentConfiguration().state == .ready, "precondition: ready before turning off")

        settings.aiEnabled = false
        runtime.update(settings: settings, agentStatuses: [readyStatus(.codex, url: fakeCodexURL)])

        let configuration = runtime.currentConfiguration()
        let snapshot = runtime.currentSnapshot()
        guard case .disabled = configuration.state else {
            throw TestFailure("expected disabled when aiEnabled is false, got \(configuration.state)")
        }
        try expectNil(configuration.agentKind)
        try expectNil(configuration.selectedModel)
        try expectNil(snapshot.executableURL, "turning AI off must clear the executable path")
    }

    func enabledWithoutAgentSelectionIsUnavailable() throws {
        var settings = AppSettings()
        settings.aiEnabled = true

        let runtime = ConversationRuntimeConfiguration()
        runtime.update(settings: settings, agentStatuses: [])

        let configuration = runtime.currentConfiguration()
        guard case .unavailable = configuration.state else {
            throw TestFailure("expected unavailable without agent selection, got \(configuration.state)")
        }
        try expectNil(configuration.agentKind)
        try expectNil(configuration.selectedModel)
        try expectNil(runtime.currentSnapshot().executableURL)
    }

    func unsupportedAgentSelectionIsUnavailable() throws {
        var settings = AppSettings()
        settings.aiEnabled = true
        settings.analysisAgent = .copilotCLI

        let runtime = ConversationRuntimeConfiguration()
        runtime.update(
            settings: settings,
            agentStatuses: [readyStatus(.copilotCLI, url: URL(fileURLWithPath: "/tmp/fixture/copilot"))]
        )

        let configuration = runtime.currentConfiguration()
        guard case .unavailable = configuration.state else {
            throw TestFailure("expected unsupported selection to be unavailable, got \(configuration.state)")
        }
        try expectNil(configuration.agentKind)
        try expectNil(runtime.currentSnapshot().executableURL)
    }

    func notReadyAgentStatusIsUnavailable() throws {
        var settings = AppSettings()
        settings.aiEnabled = true
        settings.analysisAgent = .codex

        let unreadyAvailabilities: [AnalysisAgentAvailability] = [.notInstalled, .notAuthenticated, .unknown]
        for availability in unreadyAvailabilities {
            let runtime = ConversationRuntimeConfiguration()
            runtime.update(
                settings: settings,
                agentStatuses: [AnalysisAgentStatus(kind: .codex, executableURL: fakeCodexURL, availability: availability)]
            )

            let configuration = runtime.currentConfiguration()
            guard case .unavailable = configuration.state else {
                throw TestFailure("expected unavailable for \(availability), got \(configuration.state)")
            }
            try expectNil(runtime.currentSnapshot().executableURL, "\(availability) must not expose a path")
        }
    }

    func readyStatusWithMissingURLIsUnavailable() throws {
        var settings = AppSettings()
        settings.aiEnabled = true
        settings.analysisAgent = .claudeCode

        let runtime = ConversationRuntimeConfiguration()
        runtime.update(settings: settings, agentStatuses: [readyStatus(.claudeCode, url: nil)])

        let configuration = runtime.currentConfiguration()
        guard case .unavailable = configuration.state else {
            throw TestFailure("expected unavailable when a ready status has no executable URL, got \(configuration.state)")
        }
        try expectNil(runtime.currentSnapshot().executableURL)
    }

    func statusForDifferentAgentIsUnavailable() throws {
        var settings = AppSettings()
        settings.aiEnabled = true
        settings.analysisAgent = .codex

        let runtime = ConversationRuntimeConfiguration()
        runtime.update(settings: settings, agentStatuses: [readyStatus(.claudeCode, url: fakeClaudeURL)])

        let configuration = runtime.currentConfiguration()
        guard case .unavailable = configuration.state else {
            throw TestFailure("expected unavailable when the status belongs to another agent, got \(configuration.state)")
        }
        try expectNil(runtime.currentSnapshot().executableURL, "another agent's executable must never leak")
    }

    func readySelectionProducesReadySnapshotWithModelAndURL() throws {
        var settings = AppSettings()
        settings.aiEnabled = true
        settings.analysisAgent = .claudeCode
        settings.setModel("sonnet", for: .claudeCode)

        let runtime = ConversationRuntimeConfiguration()
        runtime.update(settings: settings, agentStatuses: [readyStatus(.claudeCode, url: fakeClaudeURL)])

        let configuration = runtime.currentConfiguration()
        try expectEqual(configuration.state, .ready)
        try expectEqual(configuration.agentKind, .claudeCode)
        try expectEqual(configuration.selectedModel, "sonnet")

        let snapshot = runtime.currentSnapshot()
        try expectEqual(snapshot.executableURL, fakeClaudeURL, "snapshot must carry the same URL the status reported")
        try expectEqual(snapshot.configuration, configuration)
    }

    func readinessChangeToUnavailableClearsExecutablePath() throws {
        var settings = AppSettings()
        settings.aiEnabled = true
        settings.analysisAgent = .codex
        settings.setModel("gpt-5.6-luna", for: .codex)

        let runtime = ConversationRuntimeConfiguration()
        runtime.update(settings: settings, agentStatuses: [readyStatus(.codex, url: fakeCodexURL)])
        try expectEqual(runtime.currentConfiguration().state, .ready)
        try expectEqual(runtime.currentSnapshot().executableURL, fakeCodexURL)

        settings.aiEnabled = true
        runtime.update(
            settings: settings,
            agentStatuses: [AnalysisAgentStatus(kind: .codex, executableURL: nil, availability: .notInstalled)]
        )

        let configuration = runtime.currentConfiguration()
        guard case .unavailable = configuration.state else {
            throw TestFailure("expected unavailable after the agent lost readiness, got \(configuration.state)")
        }
        try expectNil(configuration.agentKind)
        try expectNil(configuration.selectedModel)
        try expectNil(runtime.currentSnapshot().executableURL, "losing readiness must clear the stale executable path")
    }

    static var entries: [TestEntry] {
        let tests = ConversationRuntimeConfigurationTests()
        return [
            TestEntry(suite: suiteName, name: "initialStateIsDisabledWithoutAgentOrPath") {
                try tests.initialStateIsDisabledWithoutAgentOrPath()
            },
            TestEntry(suite: suiteName, name: "turnedOffSettingsYieldDisabledAndClearPath") {
                try tests.turnedOffSettingsYieldDisabledAndClearPath()
            },
            TestEntry(suite: suiteName, name: "enabledWithoutAgentSelectionIsUnavailable") {
                try tests.enabledWithoutAgentSelectionIsUnavailable()
            },
            TestEntry(suite: suiteName, name: "unsupportedAgentSelectionIsUnavailable") {
                try tests.unsupportedAgentSelectionIsUnavailable()
            },
            TestEntry(suite: suiteName, name: "notReadyAgentStatusIsUnavailable") {
                try tests.notReadyAgentStatusIsUnavailable()
            },
            TestEntry(suite: suiteName, name: "readyStatusWithMissingURLIsUnavailable") {
                try tests.readyStatusWithMissingURLIsUnavailable()
            },
            TestEntry(suite: suiteName, name: "statusForDifferentAgentIsUnavailable") {
                try tests.statusForDifferentAgentIsUnavailable()
            },
            TestEntry(suite: suiteName, name: "readySelectionProducesReadySnapshotWithModelAndURL") {
                try tests.readySelectionProducesReadySnapshotWithModelAndURL()
            },
            TestEntry(suite: suiteName, name: "readinessChangeToUnavailableClearsExecutablePath") {
                try tests.readinessChangeToUnavailableClearsExecutablePath()
            }
        ]
    }
}
