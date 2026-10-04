import Foundation

/// Safe, generic failure for `ConfiguredConversationResponder`: a request
/// reached the responder without a verified runtime snapshot, so nothing was
/// invoked. It deliberately carries no associated data — no executable path,
/// status detail, or setting value is ever exposed.
enum ConversationResponderUnavailableError: LocalizedError, Equatable {
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "The conversation request could not be sent because no verified agent configuration was available."
        }
    }
}

/// The conversation transport wired to a runtime configuration snapshot.
///
/// The snapshot is the captured value taken at send time. This responder
/// never rereads settings or agent status, never discovers executables, and
/// never persists or logs the executable path; the path is handed only to the
/// restricted invocation boundary and appears in no prompt and no error.
///
/// The bare `ConversationResponding` entry point cannot run a CLI by
/// construction: it has no verified snapshot, so it fails with the generic
/// safe error and nothing else. The real path is the internal overload that
/// receives the snapshot explicitly; it extracts the ready configuration's
/// agent kind and selected model plus the captured executable URL, builds the
/// existing `RestrictedConversationResponder` around this responder's process
/// runner, and delegates the request.
final class ConfiguredConversationResponder: ConversationResponding {
    private let processRunner: AnalysisDiscoveryProcessRunning

    /// - Parameters:
    ///   - processRunner: The restricted process runner used by the delegated
    ///     restricted responder. Inject a fake in tests; production wiring
    ///     uses the default `DefaultAnalysisProcessRunner`.
    init(processRunner: AnalysisDiscoveryProcessRunning = DefaultAnalysisProcessRunner()) {
        self.processRunner = processRunner
    }

    /// The protocol entry point. It lacks a verified runtime snapshot, so it
    /// must never run a CLI: it throws the generic safe error immediately,
    /// without touching the process runner or any configuration source.
    public func respond(
        to request: ConversationRequest,
        context: ContextEnvelope
    ) async throws -> ConversationResponse {
        throw ConversationResponderUnavailableError.notConfigured
    }

    /// The real entry point: called with the snapshot captured at send time.
    /// When the snapshot is not a ready configuration with an agent kind and
    /// a captured executable URL, the generic safe error is thrown — again
    /// with no path or status detail. Otherwise the request and the already
    /// bounded approved context are delegated to the restricted responder.
    func respond(
        to request: ConversationRequest,
        context: ContextEnvelope,
        snapshot: ConversationRuntimeSnapshot
    ) async throws -> ConversationResponse {
        guard case .ready = snapshot.configuration.state,
              let agentKind = snapshot.configuration.agentKind,
              let executableURL = snapshot.executableURL else {
            throw ConversationResponderUnavailableError.notConfigured
        }

        let restricted = try RestrictedConversationResponder(
            agentKind: agentKind,
            selectedModelOptionID: snapshot.configuration.selectedModel,
            executableURL: executableURL,
            processRunner: processRunner
        )
        return try await restricted.respond(to: request, context: context)
    }
}
