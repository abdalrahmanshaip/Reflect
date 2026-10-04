import Foundation

/// The agent seam for the conversation service. Production transports
/// (configured supported CLI agents) implement this behind the restricted
/// invocation boundary in a later slice; tests inject fakes. The envelope is
/// the only approved evidence basis a response may cite.
public protocol ConversationResponding {
    func respond(to request: ConversationRequest, context: ContextEnvelope) async throws -> ConversationResponse
}

/// The approved-context seam for the conversation service. Production
/// builds bounded context from Reflect's own persisted stores with the
/// existing retriever; tests may inject failures. Implementations never
/// reread source histories and never contact a provider.
public protocol ConversationContextProviding {
    func buildContext(for request: ConversationRequest) throws -> ContextEnvelope
}

/// Production approved context: deterministic bounded retrieval over
/// Reflect's own versioned stores via the accepted M2 `ContextRetriever`,
/// with the request's question driving relevance. It receives no source
/// URL, cannot scan or reopen imported histories, and performs no provider
/// call. Comparison is requested so earlier-versus-recent coverage stays
/// explicit.
public struct RetrievalConversationContextProvider: ConversationContextProviding {
    private let retriever: ContextRetriever
    private let budget: BoundedContextBudget

    public init(persistence: PersistenceController, budget: BoundedContextBudget = .retrievalDefault) {
        self.retriever = ContextRetriever(persistence: persistence)
        self.budget = budget
    }

    public func buildContext(for request: ConversationRequest) throws -> ContextEnvelope {
        let retrievalRequest = ContextRetrievalRequest(
            terms: Self.retrievalTerms(for: request.question),
            requestsEarlierRecentComparison: true,
            scope: nil,
            budget: budget
        )
        return try retriever.retrieve(retrievalRequest, now: request.requestedAt)
    }

    /// Deterministic relevance terms from the question text: lowercased
    /// alphanumeric tokens of at least three characters, deduplicated in
    /// order. A question with no such tokens retrieves by recency.
    static func retrievalTerms(for text: String) -> [String] {
        var seen = Set<String>()
        var terms: [String] = []
        for token in text.components(separatedBy: CharacterSet.alphanumerics.inverted) where token.count >= 3 {
            let lowered = token.lowercased()
            if seen.insert(lowered).inserted {
                terms.append(lowered)
            }
        }
        return terms
    }
}

/// The outcome of an explicit send. `accepted` means the user message was
/// durably saved and the run was authorized; the run's own outcome is then
/// observed through `ConversationRequestState`, never inferred from this
/// value. Everything else means no invocation happened and no message was
/// saved.
public enum ConversationSendOutcome: Equatable {
    case accepted(requestID: String)
    case configurationUnavailable(reason: String)
    case emptyMessage
    case conversationNotFound
    case runAlreadyActive
    /// The user message could not be saved, so nothing was invoked and
    /// nothing was published. The exact submitted text is returned so the
    /// composer can keep it as an unsent draft.
    case saveFailed(unsentText: String)
}

/// The outcome of retrying a response whose write failed. Retrying never
/// contacts the agent again: it re-attempts the same local persistence of
/// the retained response.
public enum ConversationRetryOutcome: Equatable {
    case persisted(requestID: String)
    case stillFailed(requestID: String)
    case noRetainedResponse
}

/// The derived, observable state of one request. It combines the durable
/// record with this process's live runs so an open request is never
/// presented as finished: a request without a recorded outcome is either
/// running in this process or was interrupted by the process ending, and
/// its transmission stays unknown until an outcome exists.
public struct ConversationRequestState: Equatable {
    public enum Phase: Equatable {
        case running
        /// No outcome was recorded and this process holds no such run: the
        /// process ended before the request resolved. Transmission stays
        /// unknown.
        case interrupted
        case completed(responseMessageID: String)
        case canceled
        case failed(note: String)
        case invalidResponse(note: String)
        case responseSaveFailed(note: String)
    }

    public let requestID: String
    public let conversationID: String
    public let phase: Phase
    public let transmission: ConversationTransmission
    /// True when the process still retains an unsaved response for this
    /// request, so retrying the save does not require invoking the agent.
    public let retryAvailable: Bool
}

/// Owns the durable conversation store and coordinates explicit
/// conversation requests: persist-before-invoke user messages, bounded
/// approved context, fake-or-real agent invocation, response validation,
/// and honest run outcomes.
///
/// Boundaries:
/// - Nothing runs until an explicit `send`: loading, creating
///   conversations, reading messages, and drafts never invoke an agent and
///   never read source histories.
/// - The user message is saved before any invocation is authorized; a
///   failed save returns the unsent text and never produces a fake saved
///   conversation.
/// - Approved context comes only from `ConversationContextProviding`
///   (production: the M2 retriever over owned stores). Follow-up continuity
///   comes from the durable conversation itself, never from rereading
///   sources.
/// - Responses are validated against the request's actual envelope before
///   persistence; unknown references and malformed output are rejected
///   without repair and without inventing conclusions.
/// - Write failures keep the generated response as an explicitly retained
///   unsaved response; retrying persists it again without re-invoking.
/// - Stop cancels the run and records the honest canceled outcome; a
///   completion that arrives after a stop is suppressed entirely.
/// - Responses apply only to their own request and conversation, so
///   out-of-order completion and switching conversations cannot
///   cross-contaminate state.
///
/// The service assumes a single writer per store directory (one service
/// instance owns the conversations store), consistent with the
/// application's single store ownership.
public actor ConversationService {
    public enum ServiceError: Error, Equatable {
        /// The conversations store exists but could not be read: the service
        /// refuses to start with an empty view of a damaged store.
        case storeDamaged(message: String)
        case conversationNotFound
        case saveFailed(message: String)
    }

    /// Bounds for follow-up continuity: at most the most recent durable
    /// messages are carried into a follow-up request. Engineering values,
    /// not user-approved product constants.
    static let followUpTurnLimit = 12

    static let contextUnavailableNote = "The request was not sent because approved context could not be prepared from local stores. Check local data health in Settings."
    static let invocationFailedNote = "The agent request failed and could not be completed. Whether anything reached the provider is unknown."
    static let responseSaveFailedNote = "The response was generated but could not be saved. Retry while Reflect is open; retrying does not contact the agent again."

    private struct RunState {
        let conversationID: String
        let userMessageID: String
        let envelope: ContextEnvelope
        let configuration: ConversationConfiguration
        let runtimeSnapshot: ConversationRuntimeSnapshot?
        var invocationBegan: Bool
    }

    private struct RetainedResponse {
        let conversationID: String
        let userMessageID: String
        let response: ConversationResponse
        let configuration: ConversationConfiguration
    }

    private let persistence: PersistenceController
    private let contextProvider: ConversationContextProviding
    private let responder: ConversationResponding
    private let configuration: ConversationConfigurationProviding
    private let now: () -> Date
    private let makeID: () -> String

    /// In-memory mirror of the store, committed only after each successful
    /// write so a failed write can never masquerade as saved progress.
    private var storedConversations: [StoredConversation]
    private var activeRuns: [String: RunState] = [:]
    private var activeTasks: [String: Task<ConversationResponse, Error>] = [:]
    private var activeRunByConversation: [String: String] = [:]
    private var retainedResponses: [String: RetainedResponse] = [:]

    public init(
        persistence: PersistenceController,
        contextProvider: ConversationContextProviding,
        responder: ConversationResponding,
        configuration: ConversationConfigurationProviding,
        now: @escaping () -> Date = { Date() },
        makeID: @escaping () -> String = { UUID().uuidString }
    ) throws {
        self.persistence = persistence
        self.contextProvider = contextProvider
        self.responder = responder
        self.configuration = configuration
        self.now = now
        self.makeID = makeID
        switch persistence.loadConversationsHealth() {
        case .missing:
            self.storedConversations = []
        case .loaded(let value):
            self.storedConversations = value
        case .failed(let failure):
            throw ServiceError.storeDamaged(message: failure.userMessage)
        }
    }

    // MARK: Reading and conversations

    public func conversations() -> [ConversationRecord] {
        storedConversations.map(\.record)
    }

    public func conversation(_ id: String) -> ConversationRecord? {
        storedConversations.first { $0.record.id == id }?.record
    }

    public func messages(in conversationID: String) -> [ConversationMessage] {
        storedConversations.first { $0.record.id == conversationID }?.messages ?? []
    }

    /// Creates and durably saves a new empty conversation. A failed write
    /// throws; no conversation is published that is not on disk.
    @discardableResult
    public func createConversation() throws -> ConversationRecord {
        let timestamp = now()
        let record = ConversationRecord(id: makeID(), createdAt: timestamp, updatedAt: timestamp)
        var updated = storedConversations
        updated.append(StoredConversation(record: record, messages: []))
        do {
            try persistence.saveConversations(updated)
        } catch {
            throw ServiceError.saveFailed(message: StoreHealthMessages.saveFailed(.conversations))
        }
        storedConversations = updated
        return record
    }

    /// Persists the conversation's unsent composer draft. Draft text is
    /// never a message; it survives route changes and relaunches.
    public func setDraft(_ text: String?, for conversationID: String) throws {
        guard let index = storedConversations.firstIndex(where: { $0.record.id == conversationID }) else {
            throw ServiceError.conversationNotFound
        }
        var updated = storedConversations
        let timestamp = now()
        updated[index].record.draftText = text
        updated[index].record.draftUpdatedAt = text == nil ? nil : timestamp
        updated[index].record.updatedAt = timestamp
        do {
            try persistence.saveConversations(updated)
        } catch {
            throw ServiceError.saveFailed(message: StoreHealthMessages.saveFailed(.conversations))
        }
        storedConversations = updated
    }

    // MARK: Explicit invocation

    /// Explicitly submits a message and authorizes one agent invocation.
    /// The user message is saved before invocation; if the save fails, the
    /// exact text is returned and nothing is invoked or published.
    ///
    /// This call awaits the run's end (safe to wrap in a UI task) and always
    /// returns `.accepted` once the message is saved; the run's outcome is
    /// observed through `requestState(_:)` because the outcome belongs to
    /// the request, not to the send call.
    @discardableResult
    public func send(_ text: String, in conversationID: String) async -> ConversationSendOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .emptyMessage }
        guard let index = storedConversations.firstIndex(where: { $0.record.id == conversationID }) else {
            return .conversationNotFound
        }
        guard activeRunByConversation[conversationID] == nil else { return .runAlreadyActive }

        let configuredResponder = responder as? ConfiguredConversationResponder
        let runtimeSnapshot: ConversationRuntimeSnapshot?
        let snapshot: ConversationConfiguration
        if let runtimeConfiguration = configuration as? ConversationRuntimeConfiguration {
            let captured = runtimeConfiguration.currentSnapshot()
            runtimeSnapshot = captured
            snapshot = captured.configuration
        } else {
            runtimeSnapshot = nil
            snapshot = configuration.currentConfiguration()
        }
        guard case .ready = snapshot.state,
              configuredResponder == nil || runtimeSnapshot?.executableURL != nil
        else {
            return .configurationUnavailable(reason: Self.configurationUnavailableReason(for: snapshot.state))
        }

        // Persist the submitted user message before anything is invoked.
        let requestID = makeID()
        let userMessageID = makeID()
        let timestamp = now()
        let userMessage = ConversationMessage(
            id: userMessageID,
            conversationID: conversationID,
            speaker: .user,
            text: trimmed,
            createdAt: timestamp,
            requestID: requestID,
            transmission: .unknown
        )
        var updated = storedConversations
        updated[index].messages.append(userMessage)
        updated[index].record.messageIDs.append(userMessageID)
        updated[index].record.updatedAt = timestamp
        do {
            try persistence.saveConversations(updated)
        } catch {
            return .saveFailed(unsentText: trimmed)
        }
        storedConversations = updated

        // Bounded approved context from Reflect-owned stores only.
        let followUps = Self.followUpTurns(from: Array(updated[index].messages.dropLast()))
        let request = ConversationRequest(
            id: requestID,
            conversationID: conversationID,
            question: trimmed,
            requestedAt: timestamp,
            followUpTurns: followUps
        )
        let envelope: ContextEnvelope
        do {
            envelope = try contextProvider.buildContext(for: request)
        } catch {
            recordRunEnd(
                requestID: requestID,
                outcome: .failed(note: Self.contextUnavailableNote),
                transmission: .none
            )
            return .accepted(requestID: requestID)
        }

        // Register the run, then invoke. The task inherits this actor's
        // isolation so all state mutations stay serialized; awaiting the
        // provider call frees the actor for stop() and other conversations.
        activeRunByConversation[conversationID] = requestID
        activeRuns[requestID] = RunState(
            conversationID: conversationID,
            userMessageID: userMessageID,
            envelope: envelope,
            configuration: snapshot,
            runtimeSnapshot: runtimeSnapshot,
            invocationBegan: false
        )
        let task = Task<ConversationResponse, Error> {
            activeRuns[requestID]?.invocationBegan = true
            if let configured = configuredResponder, let captured = runtimeSnapshot {
                return try await configured.respond(to: request, context: envelope, snapshot: captured)
            }
            return try await responder.respond(to: request, context: envelope)
        }
        activeTasks[requestID] = task
        defer { cleanupRun(requestID) }

        let response: ConversationResponse
        do {
            response = try await task.value
        } catch {
            if activeRuns[requestID] != nil {
                // The run ended on its own; stop() did not record anything.
                if error is CancellationError {
                    recordRunEnd(
                        requestID: requestID,
                        outcome: .canceled,
                        transmission: Self.transmission(invocationBegan: activeRuns[requestID]?.invocationBegan ?? true)
                    )
                } else {
                    recordRunEnd(
                        requestID: requestID,
                        outcome: .failed(note: Self.invocationFailedNote),
                        transmission: Self.transmission(invocationBegan: activeRuns[requestID]?.invocationBegan ?? true)
                    )
                }
            }
            return .accepted(requestID: requestID)
        }

        guard activeRuns[requestID] != nil else {
            // The run was stopped while the call was in flight: a late
            // completion is suppressed entirely — never persisted, never
            // retained, never published.
            return .accepted(requestID: requestID)
        }

        do {
            try ResponseValidator.validate(response, expectedRequestID: requestID, envelope: envelope)
        } catch let rejection as ResponseValidationRejection {
            recordRunEnd(requestID: requestID, outcome: .invalidResponse(note: rejection.note), transmission: .sent)
            return .accepted(requestID: requestID)
        } catch {
            recordRunEnd(
                requestID: requestID,
                outcome: .invalidResponse(note: ResponseValidationRejection.emptyAnswer.note),
                transmission: .sent
            )
            return .accepted(requestID: requestID)
        }

        do {
            _ = try persistCompletedResponse(
                requestID: requestID,
                conversationID: conversationID,
                userMessageID: userMessageID,
                response: response,
                configuration: snapshot
            )
        } catch {
            // The write failed: keep the generated response explicitly
            // retained so retrying persists it without re-invoking, and
            // record the honest failed-save outcome.
            retainedResponses[requestID] = RetainedResponse(
                conversationID: conversationID,
                userMessageID: userMessageID,
                response: response,
                configuration: snapshot
            )
            recordRunEnd(requestID: requestID, outcome: .responseSaveFailed(note: Self.responseSaveFailedNote), transmission: .sent)
        }
        return .accepted(requestID: requestID)
    }

    /// Stops the run for this request, if it is still active. The task is
    /// canceled and the honest canceled outcome is recorded durably; a
    /// completion arriving afterwards is suppressed by the run's send.
    public func stop(requestID: String) {
        guard let run = activeRuns[requestID] else { return }
        let task = activeTasks[requestID]
        cleanupRun(requestID)
        task?.cancel()
        recordRunEnd(
            requestID: requestID,
            outcome: .canceled,
            transmission: Self.transmission(invocationBegan: run.invocationBegan)
        )
    }

    /// Retries persisting a retained response whose earlier write failed.
    /// The agent is never contacted again: the same validated response is
    /// written again. Without a retained response (for example after a
    /// relaunch) there is nothing to persist and no retry silently
    /// re-invokes.
    @discardableResult
    public func retryUnsavedResponse(in conversationID: String) -> ConversationRetryOutcome {
        guard let entry = retainedResponses.first(where: { $0.value.conversationID == conversationID }) else {
            return .noRetainedResponse
        }
        let requestID = entry.key
        let retained = entry.value
        do {
            _ = try persistCompletedResponse(
                requestID: requestID,
                conversationID: conversationID,
                userMessageID: retained.userMessageID,
                response: retained.response,
                configuration: retained.configuration
            )
        } catch {
            return .stillFailed(requestID: requestID)
        }
        retainedResponses[requestID] = nil
        return .persisted(requestID: requestID)
    }

    // MARK: Derived request state

    public func requestState(_ requestID: String) -> ConversationRequestState? {
        if let run = activeRuns[requestID] {
            return ConversationRequestState(
                requestID: requestID,
                conversationID: run.conversationID,
                phase: .running,
                transmission: .unknown,
                retryAvailable: false
            )
        }
        for stored in storedConversations {
            guard let message = stored.messages.last(where: { $0.requestID == requestID && $0.speaker == .user }) else {
                continue
            }
            let phase: ConversationRequestState.Phase
            var transmission = message.transmission
            switch message.requestOutcome {
            case .completed(let responseMessageID):
                phase = .completed(responseMessageID: responseMessageID)
            case .canceled:
                phase = .canceled
            case .failed(let note):
                phase = .failed(note: note)
            case .invalidResponse(let note):
                phase = .invalidResponse(note: note)
            case .responseSaveFailed(let note):
                phase = .responseSaveFailed(note: note)
            case nil:
                if retainedResponses[requestID] != nil {
                    // No outcome could be durably recorded, but this process
                    // still retains the generated response: the call
                    // completed and its save failed, so report that truth
                    // instead of the weaker interrupted/unknown state.
                    phase = .responseSaveFailed(note: Self.responseSaveFailedNote)
                    transmission = .sent
                } else {
                    phase = .interrupted
                }
            }
            return ConversationRequestState(
                requestID: requestID,
                conversationID: stored.record.id,
                phase: phase,
                transmission: transmission,
                retryAvailable: retainedResponses[requestID] != nil
            )
        }
        return nil
    }

    // MARK: Internals

    private static func transmission(invocationBegan: Bool) -> ConversationTransmission {
        invocationBegan ? .possiblySent : .none
    }

    private static func configurationUnavailableReason(for state: ConversationCapabilityState) -> String {
        switch state {
        case .ready:
            return "The conversation configuration is not ready."
        case .disabled(let reason):
            return reason
        case .unavailable(let reason):
            return reason
        }
    }

    private static func followUpTurns(from messages: [ConversationMessage]) -> [ConversationFollowUpTurn] {
        messages.suffix(followUpTurnLimit).map { ConversationFollowUpTurn(speaker: $0.speaker, text: $0.text) }
    }

    private func cleanupRun(_ requestID: String) {
        if let conversationID = activeRuns[requestID]?.conversationID,
           activeRunByConversation[conversationID] == requestID {
            activeRunByConversation[conversationID] = nil
        }
        activeRuns[requestID] = nil
        activeTasks[requestID] = nil
    }

    /// Records a durable end-state on the request's user message and saves
    /// it. In-memory state is committed only after a successful write; if
    /// the write fails, the outcome stays unrecorded (an interrupted
    /// request with unknown transmission) rather than being faked.
    private func recordRunEnd(
        requestID: String,
        outcome: ConversationRequestOutcome,
        transmission: ConversationTransmission
    ) {
        var updated = storedConversations
        guard let conversationIndex = updated.firstIndex(where: { stored in
            stored.messages.contains { $0.requestID == requestID && $0.speaker == .user }
        }) else { return }
        guard let messageIndex = updated[conversationIndex].messages.lastIndex(where: {
            $0.requestID == requestID && $0.speaker == .user
        }) else { return }
        updated[conversationIndex].messages[messageIndex].transmission = transmission
        updated[conversationIndex].messages[messageIndex].requestOutcome = outcome
        updated[conversationIndex].record.updatedAt = now()
        do {
            try persistence.saveConversations(updated)
        } catch {
            return
        }
        storedConversations = updated
    }

    /// Persists the validated assistant message together with the completed
    /// outcome in one atomic store write. Throws when the write fails; the
    /// in-memory mirror is only committed after success.
    private func persistCompletedResponse(
        requestID: String,
        conversationID: String,
        userMessageID: String,
        response: ConversationResponse,
        configuration: ConversationConfiguration
    ) throws -> String {
        var updated = storedConversations
        guard let index = updated.firstIndex(where: { $0.record.id == conversationID }) else {
            throw ServiceError.conversationNotFound
        }
        let messageID = makeID()
        let timestamp = now()
        let assistantMessage = ConversationMessage(
            id: messageID,
            conversationID: conversationID,
            speaker: .assistant,
            text: response.answerText,
            createdAt: timestamp,
            requestID: requestID,
            transmission: .sent,
            usage: response.usage,
            referencedContextItemIDs: response.referencedContextItemIDs,
            agentKind: configuration.agentKind,
            selectedModel: configuration.selectedModel
        )
        updated[index].messages.append(assistantMessage)
        updated[index].record.messageIDs.append(messageID)
        updated[index].record.updatedAt = timestamp
        if let userIndex = updated[index].messages.lastIndex(where: { $0.id == userMessageID }) {
            updated[index].messages[userIndex].transmission = .sent
            updated[index].messages[userIndex].requestOutcome = .completed(responseMessageID: messageID)
        }
        try persistence.saveConversations(updated)
        storedConversations = updated
        return messageID
    }
}
