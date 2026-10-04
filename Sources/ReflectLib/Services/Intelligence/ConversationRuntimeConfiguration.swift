import Foundation

struct ConversationRuntimeSnapshot {
    let configuration: ConversationConfiguration
    let executableURL: URL?
}

final class ConversationRuntimeConfiguration: ConversationConfigurationProviding {
    private let lock = NSLock()
    private var configuration: ConversationConfiguration
    private var executableURL: URL?

    init() {
        self.configuration = ConversationConfiguration(
            state: .disabled(reason: "AI conversation is turned off in Settings."),
            agentKind: nil,
            selectedModel: nil
        )
        self.executableURL = nil
    }

    func update(settings: AppSettings, agentStatuses: [AnalysisAgentStatus]) {
        let resolved = Self.resolve(settings: settings, agentStatuses: agentStatuses)
        lock.lock()
        defer { lock.unlock() }
        configuration = resolved.configuration
        executableURL = resolved.executableURL
    }

    func currentConfiguration() -> ConversationConfiguration {
        lock.lock()
        defer { lock.unlock() }
        return configuration
    }

    func currentSnapshot() -> ConversationRuntimeSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return ConversationRuntimeSnapshot(configuration: configuration, executableURL: executableURL)
    }

    private static func resolve(settings: AppSettings, agentStatuses: [AnalysisAgentStatus]) -> ConversationRuntimeSnapshot {
        guard settings.aiEnabled else {
            return ConversationRuntimeSnapshot(
                configuration: ConversationConfiguration(
                    state: .disabled(reason: "AI conversation is turned off in Settings."),
                    agentKind: nil,
                    selectedModel: nil
                ),
                executableURL: nil
            )
        }
        guard let selected = settings.analysisAgent, AnalysisAgentKind.supported.contains(selected) else {
            return ConversationRuntimeSnapshot(
                configuration: ConversationConfiguration(
                    state: .unavailable(reason: "Choose a supported analysis agent in Settings to start a conversation."),
                    agentKind: nil,
                    selectedModel: nil
                ),
                executableURL: nil
            )
        }
        guard let status = agentStatuses.first(where: { $0.kind == selected }),
              status.availability == .ready,
              let executableURL = status.executableURL else {
            return ConversationRuntimeSnapshot(
                configuration: ConversationConfiguration(
                    state: .unavailable(reason: "\(selected.displayName) is not ready on this machine."),
                    agentKind: nil,
                    selectedModel: nil
                ),
                executableURL: nil
            )
        }
        return ConversationRuntimeSnapshot(
            configuration: .ready(agentKind: selected, selectedModel: settings.model(for: selected)),
            executableURL: executableURL
        )
    }
}
