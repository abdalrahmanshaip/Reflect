import AppKit

enum AnalysisAgentIconResolver {
    static func image(for kind: AnalysisAgentKind) -> NSImage? {
        for path in candidateAppPaths(for: kind) {
            if FileManager.default.fileExists(atPath: path) {
                return NSWorkspace.shared.icon(forFile: path)
            }
        }
        return nil
    }

    private static func candidateAppPaths(for kind: AnalysisAgentKind) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch kind {
        case .codex:
            return ["/Applications/Codex.app", "\(home)/Applications/Codex.app"]
        case .claudeCode:
            return [
                "/Applications/Claude.app",
                "/Applications/Claude Code.app",
                "\(home)/Applications/Claude.app",
                "\(home)/Applications/Claude Code.app"
            ]
        case .copilotCLI:
            return ["/Applications/GitHub Copilot.app", "\(home)/Applications/GitHub Copilot.app"]
        }
    }
}
