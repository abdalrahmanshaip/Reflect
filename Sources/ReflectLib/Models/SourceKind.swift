import Foundation

/// Sources Reflect can observe. Availability and verification status are always shown honestly.
public enum SourceKind: String, Codable, CaseIterable, Hashable, Identifiable {
    case codex
    case claudeCode = "claude_code"
    case copilotCLI = "copilot_cli"
    case cursor
    case vscode
    case gitLocal = "git_local"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .codex: return "Codex CLI"
        case .claudeCode: return "Claude Code"
        case .copilotCLI: return "Copilot CLI"
        case .cursor: return "Cursor"
        case .vscode: return "VS Code"
        case .gitLocal: return "Git (local repository)"
        }
    }

    /// Only line-oriented formats that this build verifies against synthetic fixtures are importable.
    public var formatVerified: Bool {
        switch self {
        case .codex, .claudeCode, .copilotCLI, .gitLocal: return true
        case .cursor, .vscode: return false
        }
    }

    /// Home-relative roots scanned for availability metadata. Git is user-selected instead.
    public var defaultHomeRelativeRoots: [String] {
        switch self {
        case .codex: return [".codex/sessions"]
        case .claudeCode: return [".claude/projects"]
        case .copilotCLI: return [".copilot/session-state"]
        case .cursor: return ["Library/Application Support/Cursor/User/workspaceStorage"]
        case .vscode: return ["Library/Application Support/Code/User/workspaceStorage"]
        case .gitLocal: return []
        }
    }
}
