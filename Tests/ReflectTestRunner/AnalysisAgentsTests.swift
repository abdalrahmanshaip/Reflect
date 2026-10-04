import Foundation
@testable import ReflectLib

private final class FakeExecutableLocator: ExecutableLocating {
    var paths: [String: URL] = [:]

    func executableURL(for command: String) -> URL? {
        paths[command]
    }
}

private final class FakeAnalysisProcessRunner: AnalysisProcessRunning, AnalysisDiscoveryProcessRunning {
    var responses: [AnalysisProcessResult] = []
    var invocations: [AnalysisProcessInvocation] = []
    var failures: [Error] = []

    func run(_ invocation: AnalysisProcessInvocation) throws -> AnalysisProcessResult {
        invocations.append(invocation)
        return responses.isEmpty
            ? AnalysisProcessResult(stdout: Data(), stderr: Data(), terminationStatus: 0)
            : responses.removeFirst()
    }

    func run(_ invocation: AnalysisProcessInvocation) async throws -> AnalysisProcessResult {
        invocations.append(invocation)
        if !failures.isEmpty {
            throw failures.removeFirst()
        }
        return responses.isEmpty
            ? AnalysisProcessResult(stdout: Data(), stderr: Data(), terminationStatus: 0)
            : responses.removeFirst()
    }
}

struct AnalysisAgentsTests {
    static let suiteName = "AnalysisAgentsTests"

    func onlySupportedAgentsAreExposed() throws {
        try expectEqual(AnalysisAgentKind.supported, [.codex, .claudeCode])
        try expectFalse(AnalysisAgentKind.supported.contains(.copilotCLI), "Copilot is not supported without a verified local adapter")
    }

    func discoveryRequiresInstalledAndAuthenticatedCLI() throws {
        let locator = FakeExecutableLocator()
        locator.paths["codex"] = URL(fileURLWithPath: "/tmp/fixture/codex")
        locator.paths["claude"] = URL(fileURLWithPath: "/tmp/fixture/claude")

        let runner = FakeAnalysisProcessRunner()
        runner.responses = [
            AnalysisProcessResult(stdout: Data("Logged in using ChatGPT".utf8), stderr: Data(), terminationStatus: 0),
            AnalysisProcessResult(stdout: Data("Not logged in".utf8), stderr: Data(), terminationStatus: 1)
        ]

        let statuses = try Fixtures.awaitAsync {
            await AnalysisAgentDiscovery(runner: runner, locator: locator).discover()
        }

        try expectEqual(statuses.count, 2)
        try expectEqual(statuses.first(where: { $0.kind == .codex })?.availability, .ready)
        try expectEqual(statuses.first(where: { $0.kind == .claudeCode })?.availability, .notAuthenticated)
        try expectTrue(statuses.contains(where: { $0.kind == .codex && $0.isReady }))
        try expectEqual(runner.invocations.map(\.arguments), [["login", "status"], ["auth", "status", "--json"]])
    }

    func unknownAuthenticationNeverBecomesReady() throws {
        let locator = FakeExecutableLocator()
        locator.paths["codex"] = URL(fileURLWithPath: "/tmp/fixture/codex")
        let runner = FakeAnalysisProcessRunner()
        runner.responses = [
            AnalysisProcessResult(stdout: Data("status unavailable".utf8), stderr: Data(), terminationStatus: 0)
        ]

        let statuses = try Fixtures.awaitAsync {
            await AnalysisAgentDiscovery(runner: runner, locator: locator).discover()
        }

        try expectEqual(statuses.first(where: { $0.kind == .codex })?.availability, .unknown)
        try expectFalse(statuses.contains(where: \.isReady), "unknown authentication cannot be shown as Ready")
    }

    /// An absent executable is honestly "not installed" and never starts a
    /// status process for it.
    func absentExecutableIsNotInstalledWithoutInvokingAProcess() throws {
        let locator = FakeExecutableLocator()
        let runner = FakeAnalysisProcessRunner()

        let statuses = try Fixtures.awaitAsync {
            await AnalysisAgentDiscovery(runner: runner, locator: locator).discover()
        }

        try expectEqual(statuses.map(\.availability), [.notInstalled, .notInstalled])
        try expectTrue(runner.invocations.isEmpty, "missing executables must not launch status processes")
        try expectFalse(statuses.contains(where: \.isReady))
    }

    /// A timed-out or hung installed agent stays honest: unknown, never
    /// ready and never "not installed".
    func timedOutInstalledAgentIsUnknown() throws {
        let locator = FakeExecutableLocator()
        locator.paths["codex"] = URL(fileURLWithPath: "/tmp/fixture/codex")
        let runner = FakeAnalysisProcessRunner()
        runner.failures = [AnalysisProcessError.timedOut]

        let statuses = try Fixtures.awaitAsync {
            await AnalysisAgentDiscovery(runner: runner, locator: locator).discover()
        }

        try expectEqual(statuses.first(where: { $0.kind == .codex })?.availability, .unknown)
        try expectEqual(statuses.first(where: { $0.kind == .claudeCode })?.availability, .notInstalled)
        try expectFalse(statuses.contains(where: \.isReady), "a timed-out agent must never be shown as Ready")
    }

    func settingsRetainIndependentModelChoicesPerAgent() throws {
        var settings = AppSettings()
        settings.analysisAgent = .codex
        settings.setModel("gpt-5.6-luna", for: .codex)
        settings.setModel("sonnet", for: .claudeCode)

        try expectEqual(settings.model(for: .codex), "gpt-5.6-luna")
        try expectEqual(settings.model(for: .claudeCode), "sonnet")

        settings.analysisAgent = .claudeCode
        try expectEqual(settings.model(for: .codex), "gpt-5.6-luna")
        try expectEqual(settings.model(for: .claudeCode), "sonnet")
    }

    func legacySettingsDecodeWithoutDiscardingUnrelatedValues() throws {
        let directory = Fixtures.makeTempDirectory("analysis-settings-migration")
        let settingsURL = directory.appendingPathComponent("settings.json")
        let legacy = """
        {
          "aiEnabled": true,
          "enabledSources": ["codex", "claude_code"],
          "exclusions": ["PrivateProject"],
          "gitRepositoryPath": "/tmp/fixture-repo",
          "maxPreviewCharacters": 80,
          "providerEndpoint": "https://provider.example.invalid",
          "providerModel": "legacy-model",
          "pricePerMillionInput": 1.5,
          "pricePerMillionOutput": 6.0,
          "usageMode": "requested"
        }
        """
        try legacy.data(using: .utf8)!.write(to: settingsURL)

        let settings = try PersistenceController(directory: directory).loadSettings()

        try expectTrue(settings.aiEnabled)
        try expectEqual(settings.exclusions, ["PrivateProject"])
        try expectEqual(settings.gitRepositoryPath, "/tmp/fixture-repo")
        try expectEqual(settings.maxPreviewCharacters, 80)
        try expectNil(settings.analysisAgent, "legacy endpoint configuration cannot infer a supported agent")
        try expectTrue(settings.modelSelections.isEmpty, "legacy model must not be treated as a verified model choice")
    }

    func analysisInvocationUsesSelectedEvidenceAndSafeArguments() throws {
        var settings = AppSettings()
        settings.aiEnabled = true
        settings.analysisAgent = .claudeCode
        settings.setModel("sonnet", for: .claudeCode)

        let runner = FakeAnalysisProcessRunner()
        runner.responses = [
            AnalysisProcessResult(stdout: Data("Synthetic interpretation".utf8), stderr: Data("private cli error".utf8), terminationStatus: 0)
        ]
        let status = AnalysisAgentStatus(kind: .claudeCode, executableURL: URL(fileURLWithPath: "/tmp/fixture/claude"), availability: .ready)

        let result = try AnalysisService().run(
            selectedEvents: Fixtures.dayEvents(count: 2),
            settings: settings,
            agent: status,
            processRunner: runner,
            temporaryDirectory: Fixtures.makeTempDirectory("analysis-run")
        )

        let invocation = try require(runner.invocations.first)
        try expectEqual(result.text, "Synthetic interpretation")
        try expectEqual(invocation.executableURL.path, "/tmp/fixture/claude")
        try expectTrue(invocation.arguments.contains("--no-session-persistence"))
        try expectTrue(invocation.arguments.contains("--restricted"))
        try expectTrue(invocation.arguments.contains("--tools"))
        try expectTrue(invocation.arguments.contains("sonnet"))
        try expectFalse(invocation.arguments.contains("--dangerously-skip-permissions"))
        try expectFalse(invocation.arguments.contains("--add-dir"))

        let input = String(decoding: invocation.input, as: UTF8.self)
        try expectTrue(input.contains("fixture-event-0"))
        try expectTrue(input.contains("fixture-event-1"))
        try expectTrue(input.contains("Synthetic interpretation") == false, "CLI output must not be included in the next input")
    }

    func codexInvocationUsesReadOnlyIsolatedArguments() throws {
        var settings = AppSettings()
        settings.aiEnabled = true
        settings.analysisAgent = .codex

        let runner = FakeAnalysisProcessRunner()
        runner.responses = [
            AnalysisProcessResult(stdout: Data("Synthetic interpretation".utf8), stderr: Data(), terminationStatus: 0)
        ]
        let status = AnalysisAgentStatus(kind: .codex, executableURL: URL(fileURLWithPath: "/tmp/fixture/codex"), availability: .ready)

        _ = try AnalysisService().run(
            selectedEvents: Fixtures.dayEvents(count: 1),
            settings: settings,
            agent: status,
            processRunner: runner,
            temporaryDirectory: Fixtures.makeTempDirectory("analysis-codex-run")
        )

        let invocation = try require(runner.invocations.first)
        try expectTrue(invocation.arguments.contains("--sandbox"))
        try expectTrue(invocation.arguments.contains("read-only"))
        try expectTrue(invocation.arguments.contains("--ask-for-approval"))
        try expectTrue(invocation.arguments.contains("never"))
        try expectTrue(invocation.arguments.contains("--ignore-rules"))
        try expectFalse(invocation.arguments.contains("--dangerously-bypass-approvals-and-sandbox"))
        try expectFalse(invocation.arguments.contains("--add-dir"))
        try expectTrue(String(decoding: invocation.input, as: UTF8.self).contains("Do not use tools"))
    }

    static var entries: [TestEntry] {
        let tests = AnalysisAgentsTests()
        return [
            TestEntry(suite: suiteName, name: "onlySupportedAgentsAreExposed") { try tests.onlySupportedAgentsAreExposed() },
            TestEntry(suite: suiteName, name: "discoveryRequiresInstalledAndAuthenticatedCLI") { try tests.discoveryRequiresInstalledAndAuthenticatedCLI() },
            TestEntry(suite: suiteName, name: "unknownAuthenticationNeverBecomesReady") { try tests.unknownAuthenticationNeverBecomesReady() },
            TestEntry(suite: suiteName, name: "absentExecutableIsNotInstalledWithoutInvokingAProcess") {
                try tests.absentExecutableIsNotInstalledWithoutInvokingAProcess()
            },
            TestEntry(suite: suiteName, name: "timedOutInstalledAgentIsUnknown") {
                try tests.timedOutInstalledAgentIsUnknown()
            },
            TestEntry(suite: suiteName, name: "settingsRetainIndependentModelChoicesPerAgent") { try tests.settingsRetainIndependentModelChoicesPerAgent() },
            TestEntry(suite: suiteName, name: "legacySettingsDecodeWithoutDiscardingUnrelatedValues") { try tests.legacySettingsDecodeWithoutDiscardingUnrelatedValues() },
            TestEntry(suite: suiteName, name: "analysisInvocationUsesSelectedEvidenceAndSafeArguments") {
                try tests.analysisInvocationUsesSelectedEvidenceAndSafeArguments()
            },
            TestEntry(suite: suiteName, name: "codexInvocationUsesReadOnlyIsolatedArguments") {
                try tests.codexInvocationUsesReadOnlyIsolatedArguments()
            }
        ]
    }
}
