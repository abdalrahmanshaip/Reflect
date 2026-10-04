import Foundation

/// Analysis runners that Reflect can invoke. Import sources are intentionally
/// separate from this list: an importer being supported does not make its CLI
/// safe or documented for analysis.
public enum AnalysisAgentKind: String, Codable, CaseIterable, Hashable, Identifiable {
    case codex
    case claudeCode = "claude_code"
    case copilotCLI = "copilot_cli"

    public var id: String { rawValue }

    /// Copilot remains out of the UI until a safe, locally verifiable adapter is
    /// available. Keeping it in the model makes the boundary explicit without
    /// presenting an unsupported executable as an agent.
    public static var supported: [AnalysisAgentKind] {
        [.codex, .claudeCode]
    }

    public var displayName: String {
        switch self {
        case .codex: return "Codex CLI"
        case .claudeCode: return "Claude Code"
        case .copilotCLI: return "Copilot CLI"
        }
    }

    public var executableName: String {
        switch self {
        case .codex: return "codex"
        case .claudeCode: return "claude"
        case .copilotCLI: return "copilot"
        }
    }

    public var iconSystemName: String {
        switch self {
        case .codex: return "sparkles"
        case .claudeCode: return "sun.max"
        case .copilotCLI: return "person.2"
        }
    }

    /// Only aliases documented by the current CLI documentation are exposed.
    /// Codex's installed help accepts a model flag but does not publish a
    /// stable model catalog, so it intentionally exposes only its default.
    public var modelOptions: [AnalysisModelOption] {
        switch self {
        case .codex:
            return [.agentDefault]
        case .claudeCode:
            return [.agentDefault, AnalysisModelOption(id: "sonnet", title: "Sonnet"), AnalysisModelOption(id: "opus", title: "Opus")]
        case .copilotCLI:
            return [.agentDefault]
        }
    }

    var authenticationArguments: [String] {
        switch self {
        case .codex: return ["login", "status"]
        case .claudeCode: return ["auth", "status", "--json"]
        case .copilotCLI: return []
        }
    }

    func analysisArguments(model: String?) -> [String] {
        let chosenModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self {
        case .codex:
            var arguments = [
                "exec",
                "--ephemeral",
                "--ignore-user-config",
                "--sandbox", "read-only",
                "--ask-for-approval", "never",
                "--ignore-rules",
                "--skip-git-repo-check",
                "--color", "never"
            ]
            if let chosenModel, !chosenModel.isEmpty {
                arguments += ["--model", chosenModel]
            }
            return arguments
        case .claudeCode:
            var arguments = [
                "--print",
                "--output-format", "text",
                "--input-format", "text",
                "--no-session-persistence",
                "--safe-mode",
                "--restricted",
                "--tools", "",
                "--permission-mode", "dontAsk"
            ]
            if let chosenModel, !chosenModel.isEmpty {
                arguments += ["--model", chosenModel]
            }
            return arguments
        case .copilotCLI:
            return []
        }
    }
}

public struct AnalysisModelOption: Codable, Equatable, Hashable, Identifiable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    public static let agentDefault = AnalysisModelOption(id: "", title: "Agent default")
}

public enum AnalysisAgentAvailability: String, Codable, Equatable {
    case ready
    case notInstalled
    case notAuthenticated
    case unknown
}

public struct AnalysisAgentStatus: Equatable, Identifiable {
    public let kind: AnalysisAgentKind
    public let executableURL: URL?
    public let availability: AnalysisAgentAvailability

    public var id: String { kind.id }
    public var isReady: Bool { availability == .ready }

    public init(kind: AnalysisAgentKind, executableURL: URL?, availability: AnalysisAgentAvailability) {
        self.kind = kind
        self.executableURL = executableURL
        self.availability = availability
    }
}
