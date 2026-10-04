import Foundation

/// Whether a conversation invocation may proceed, and why not when it may
/// not. The states are exactly distinct so a missing configuration is never
/// presented as ready, and a deliberate opt-out is never presented as a
/// machine-level unavailability:
///
/// - `ready`: a supported agent is explicitly enabled and selected. Only
///   this state authorizes invocation, and invocation still requires an
///   explicit user send action.
/// - `disabled`: the user turned AI conversation off. A user choice, not an
///   error.
/// - `unavailable`: no agent is selected (or the selection is not usable),
///   so requests cannot be invoked on this machine right now.
public enum ConversationCapabilityState: Equatable {
    case ready
    case disabled(reason: String)
    case unavailable(reason: String)
}

/// A configuration snapshot taken at send time. The snapshot travels with
/// the run so a configuration change mid-run cannot silently alter which
/// agent and model a running request uses.
public struct ConversationConfiguration: Equatable {
    public let state: ConversationCapabilityState
    public let agentKind: AnalysisAgentKind?
    public let selectedModel: String?

    public init(state: ConversationCapabilityState, agentKind: AnalysisAgentKind? = nil, selectedModel: String? = nil) {
        self.state = state
        self.agentKind = agentKind
        self.selectedModel = selectedModel
    }

    public static func ready(agentKind: AnalysisAgentKind, selectedModel: String?) -> ConversationConfiguration {
        ConversationConfiguration(state: .ready, agentKind: agentKind, selectedModel: selectedModel)
    }
}

/// The configuration seam for the conversation service. Production reads
/// the user's explicit settings; tests inject states directly. Nothing in
/// this seam discovers executables or contacts providers — deeper
/// availability verification belongs to the transport slice.
public protocol ConversationConfigurationProviding {
    func currentConfiguration() -> ConversationConfiguration
}

/// Production configuration: maps the user's explicit analysis settings to
/// conversation capability. AI stays off until the user enables it and
/// selects a supported agent; no launch-time or background check occurs.
public struct SettingsConversationConfigurationProvider: ConversationConfigurationProviding {
    private let settingsProvider: () -> AppSettings

    public init(settingsProvider: @escaping () -> AppSettings) {
        self.settingsProvider = settingsProvider
    }

    public func currentConfiguration() -> ConversationConfiguration {
        let settings = settingsProvider()
        guard settings.aiEnabled else {
            return ConversationConfiguration(
                state: .disabled(reason: "AI conversation is turned off in Settings."),
                agentKind: nil,
                selectedModel: nil
            )
        }
        guard let agent = settings.analysisAgent, AnalysisAgentKind.supported.contains(agent) else {
            return ConversationConfiguration(
                state: .unavailable(reason: "Choose a supported analysis agent in Settings to start a conversation."),
                agentKind: nil,
                selectedModel: nil
            )
        }
        return ConversationConfiguration.ready(agentKind: agent, selectedModel: settings.model(for: agent))
    }
}
