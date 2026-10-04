import Foundation

/// A validated-capable response produced by a `ConversationResponding`
/// agent for one request. The raw output is untrusted: it becomes a durable
/// message only after `ResponseValidator` accepts it against the request's
/// actual context envelope.
///
/// This slice deliberately carries no assessment claims or profile
/// proposals — those contracts and their validation arrive with the profile
/// milestone. References here are the only structured output, and unknown
/// references cause rejection, never silent repair or invented competence
/// conclusions.
public struct ConversationResponse: Codable, Hashable {
    /// The request this response claims to answer. A mismatch is a
    /// validation rejection.
    public let requestID: String
    public let answerText: String
    /// Supporting context item IDs the agent cites. Every ID must be an
    /// item actually included in the request's context envelope.
    public let referencedContextItemIDs: [String]
    /// A model identifier reported by the provider, when the transport
    /// receives one. `nil` means the model is unknown — never guessed from
    /// configuration alone.
    public let modelReportedByProvider: String?
    /// Provider-reported usage. `nil` means nothing was reported and usage
    /// and cost stay unknown; no zero is ever fabricated.
    public let usage: ConversationUsage?

    public init(
        requestID: String,
        answerText: String,
        referencedContextItemIDs: [String] = [],
        modelReportedByProvider: String? = nil,
        usage: ConversationUsage? = nil
    ) {
        self.requestID = requestID
        self.answerText = answerText
        self.referencedContextItemIDs = referencedContextItemIDs
        self.modelReportedByProvider = modelReportedByProvider
        self.usage = usage
    }
}
