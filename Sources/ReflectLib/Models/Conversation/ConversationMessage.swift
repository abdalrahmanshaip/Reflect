import Foundation

/// One durable message inside a Reflect conversation. Messages are the
/// persisted unit of conversation history: a user message is saved before any
/// provider invocation is authorized, and an assistant message is saved only
/// after its response passed validation. A message that could not be saved is
/// never published; unsent text stays an explicit draft or send outcome
/// instead of a fake saved message.
///
/// Provenance stays exact: user messages are the user's own words, assistant
/// messages are generated content. Neither is ever promoted into the observed
/// evidence stores by this slice, and a generated message never becomes
/// evidence of anything by itself.
public struct ConversationMessage: Codable, Hashable, Identifiable {
    /// App-owned stable identity: a `UUID` string in the shared plain
    /// `String` ID type (accepted M1 identity rules).
    public let id: String
    public let conversationID: String
    public let speaker: ConversationSpeaker
    /// The exact message text. For user messages this is the submitted text;
    /// for assistant messages this is the validated generated answer.
    public let text: String
    public let createdAt: Date
    /// The conversation request this message belongs to: the request the user
    /// submitted (user messages) or the request that produced the response
    /// (assistant messages). Always set for persisted messages in this slice.
    public let requestID: String?
    /// Honest transmission state of the request this message belongs to.
    /// For user messages this tracks the request's outcome; for assistant
    /// messages it is always `.sent` because the message exists only after a
    /// completed provider call.
    public var transmission: ConversationTransmission
    /// The durable outcome of the request this user message submitted.
    /// `nil` means no outcome was ever recorded: the request is still
    /// running in this process, or the process ended before the run
    /// resolved — an interrupted request whose transmission stays unknown.
    /// Assistant messages never carry an outcome.
    public var requestOutcome: ConversationRequestOutcome?
    /// Provider-reported usage. `nil` means nothing was reported and the
    /// usage — including cost — stays unknown. No zero is ever fabricated.
    public let usage: ConversationUsage?
    /// Validated supporting context references for assistant messages: every
    /// ID was checked against the request's actual context envelope. Empty
    /// for user messages.
    public let referencedContextItemIDs: [String]
    /// The locally selected agent kind for assistant messages, from the
    /// configuration snapshot at invocation time.
    public let agentKind: AnalysisAgentKind?
    /// The locally selected model for assistant messages, from the same
    /// snapshot. `nil` means the agent default was selected; what the agent
    /// actually ran is not reported by the current transport and stays
    /// unknown.
    public let selectedModel: String?

    public init(
        id: String,
        conversationID: String,
        speaker: ConversationSpeaker,
        text: String,
        createdAt: Date,
        requestID: String?,
        transmission: ConversationTransmission,
        requestOutcome: ConversationRequestOutcome? = nil,
        usage: ConversationUsage? = nil,
        referencedContextItemIDs: [String] = [],
        agentKind: AnalysisAgentKind? = nil,
        selectedModel: String? = nil
    ) {
        self.id = id
        self.conversationID = conversationID
        self.speaker = speaker
        self.text = text
        self.createdAt = createdAt
        self.requestID = requestID
        self.transmission = transmission
        self.requestOutcome = requestOutcome
        self.usage = usage
        self.referencedContextItemIDs = referencedContextItemIDs
        self.agentKind = agentKind
        self.selectedModel = selectedModel
    }
}

/// Who produced a message. The distinction is structural: user text is
/// user content, assistant text is generated content. Neither speaker value
/// ever asserts or implies competence by itself.
public enum ConversationSpeaker: String, Codable, CaseIterable, Hashable {
    case user
    case assistant
}

/// Whether a request's content may have reached the configured provider.
/// The states are exactly distinct so an unknown outcome is never presented
/// as a definite "nothing was sent":
///
/// - `none`: the request definitively never reached a provider (the run
///   failed or was stopped before invocation began).
/// - `sent`: the provider call completed (the response or its failure was
///   received back).
/// - `possiblySent`: the provider call started and then the run was stopped
///   or failed; what the provider received or processed is unknown, and
///   cancellation cannot retract anything already transmitted.
/// - `unknown`: no outcome was recorded — the request is still running in
///   this process, or the process ended before the run resolved. Unknown
///   stays unknown; it is never smoothed into `none`.
public enum ConversationTransmission: String, Codable, CaseIterable, Hashable {
    case none
    case sent
    case possiblySent = "possibly_sent"
    case unknown
}

/// Provider-reported usage figures. Every field is optional: a `nil` field
/// means the provider did not report that figure, and unknown usage —
/// including unknown cost — is reported as unknown, never as zero.
public struct ConversationUsage: Codable, Hashable {
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let estimatedCostUSD: Double?

    public init(inputTokens: Int?, outputTokens: Int?, estimatedCostUSD: Double?) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.estimatedCostUSD = estimatedCostUSD
    }
}

/// The durable outcome of one conversation request, recorded on the user
/// message that submitted it. The states are exactly distinct so a saved
/// response is never confused with a response that was generated but could
/// not be saved, and a rejected response is never presented as saved. Notes
/// are safe English: they never quote provider output or payload text.
public enum ConversationRequestOutcome: Codable, Hashable {
    /// The validated response was persisted under this message ID.
    case completed(responseMessageID: String)
    /// The run was stopped. What the provider received stays unknown when
    /// invocation had begun; the message's transmission field distinguishes.
    case canceled
    /// The run failed before producing a usable response.
    case failed(note: String)
    /// The agent's output failed validation (empty, mismatched, or citing
    /// unknown references) and was rejected without repair. No competence
    /// conclusion was invented from it.
    case invalidResponse(note: String)
    /// The response passed validation but its write failed. The response is
    /// retained for retry without re-invoking the agent, for as long as this
    /// process runs.
    case responseSaveFailed(note: String)
}
