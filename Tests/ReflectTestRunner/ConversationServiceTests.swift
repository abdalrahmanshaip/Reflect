import Foundation
@testable import ReflectLib

private extension NSLock {
    func locked<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

/// Awaits throwing async service work from a synchronous test entry.
private func awaitAsyncThrows<T: Sendable>(_ body: @escaping @Sendable () async throws -> T) throws -> T {
    let box = AsyncResultBox<Result<T, Error>>()
    Task.detached {
        do {
            box.fulfill(.success(try await body()))
        } catch {
            box.fulfill(.failure(error))
        }
    }
    guard box.semaphore.wait(timeout: .now() + 30) == .success else {
        throw TestFailure("async test work did not finish within 30s")
    }
    guard let result = box.take() else {
        throw TestFailure("async test work produced no result")
    }
    return try result.get()
}

/// M3 slice 1 coverage for the durable conversation service: persist before
/// invoke, durable follow-up continuity without source rereads, bounded
/// approved context, invalid response handling, write-failure recovery with
/// retry that never re-invokes, stop with late-completion suppression,
/// out-of-order and cross-conversation isolation, relaunch, drafts,
/// unavailable configuration, no operation without explicit invocation, and
/// truthful unknown transmission/usage states. The agent is always a fake;
/// every fixture is synthetic and lives in fresh temporary stores. No real
/// history is read and no provider is contacted.
struct ConversationServiceTests {
    static let suiteName = "ConversationServiceTests"

    private let startDate = Date(timeIntervalSince1970: 1_767_614_400) // 2026-01-05T12:00:00Z

    // MARK: Helpers

    /// A monotonic synthetic clock so every persisted timestamp is distinct
    /// without depending on the host clock.
    final class TestClock {
        private var current: Date
        init(from start: Date) { current = start }
        func tick() -> Date {
            current = current.addingTimeInterval(1)
            return current
        }
    }

    /// Wait gate for gated fake-agent behavior. It fails open after a
    /// timeout so a regression surfaces as a failed assertion instead of a
    /// hung suite.
    final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var isOpen = false

        func open() {
            lock.lock()
            isOpen = true
            lock.unlock()
        }

        func wait(ignoringCancellation: Bool, timeout: TimeInterval = 15) async throws {
            let deadline = Date().addingTimeInterval(timeout)
            while true {
                if lockedCheck() { return }
                if !ignoringCancellation {
                    try Task.checkCancellation()
                }
                if Date() >= deadline { return }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }

        private func lockedCheck() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return isOpen
        }
    }

    /// The fake conversation agent. It records every invocation and follows
    /// an injected behavior script; it never contacts anything real.
    final class FakeConversationAgent: ConversationResponding, @unchecked Sendable {
        /// Scripted behaviors. Answer behaviors resolve their request ID
        /// against the actual request at invocation time, exactly as a real
        /// transport would.
        enum Behavior {
            case answer(text: String, references: [String] = [])
            case failing(Error)
            case gated(Gate, text: String, references: [String], ignoresCancellation: Bool)
            case parkedUntilCanceled
        }

        struct AgentError: Error {}

        private let lock = NSLock()
        private var behaviors: [Behavior]
        private var received: [(request: ConversationRequest, context: ContextEnvelope)] = []
        private let onInvoke: ((ConversationRequest, ContextEnvelope) -> Void)?

        init(behaviors: [Behavior] = [], onInvoke: ((ConversationRequest, ContextEnvelope) -> Void)? = nil) {
            self.behaviors = behaviors
            self.onInvoke = onInvoke
        }

        var callCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return received.count
        }

        var calls: [(request: ConversationRequest, context: ContextEnvelope)] {
            lock.lock()
            defer { lock.unlock() }
            return received
        }

        static func response(requestID: String, text: String, references: [String] = []) -> ConversationResponse {
            ConversationResponse(requestID: requestID, answerText: text, referencedContextItemIDs: references)
        }

        func respond(to request: ConversationRequest, context: ContextEnvelope) async throws -> ConversationResponse {
            let behavior: Behavior = lock.locked {
                let next = behaviors.isEmpty
                    ? .answer(text: "Synthetic answer to: \(request.question)")
                    : behaviors.removeFirst()
                received.append((request, context))
                return next
            }
            onInvoke?(request, context)
            switch behavior {
            case .answer(let text, let references):
                return ConversationResponse(
                    requestID: request.id,
                    answerText: text,
                    referencedContextItemIDs: references
                )
            case .failing(let error):
                throw error
            case .gated(let gate, let text, let references, let ignoresCancellation):
                try await gate.wait(ignoringCancellation: ignoresCancellation)
                return ConversationResponse(
                    requestID: request.id,
                    answerText: text,
                    referencedContextItemIDs: references
                )
            case .parkedUntilCanceled:
                while true {
                    try Task.checkCancellation()
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
            }
        }
    }

    struct StaticConfiguration: ConversationConfigurationProviding {
        let configuration: ConversationConfiguration
        func currentConfiguration() -> ConversationConfiguration { configuration }
    }

    struct ThrowingContextProvider: ConversationContextProviding {
        struct Failure: Error {}
        func buildContext(for request: ConversationRequest) throws -> ContextEnvelope { throw Failure() }
    }

    /// A send running in the background so tests can act on it mid-flight.
    final class SendJob {
        private let box = AsyncResultBox<ConversationSendOutcome>()

        init(_ service: ConversationService, _ text: String, conversationID: String) {
            Task.detached {
                let outcome = await service.send(text, in: conversationID)
                self.box.fulfill(outcome)
            }
        }

        func awaitResult(timeout: TimeInterval = 30) throws -> ConversationSendOutcome {
            guard box.semaphore.wait(timeout: .now() + timeout) == .success else {
                throw TestFailure("the send job did not finish in time")
            }
            guard let outcome = box.take() else {
                throw TestFailure("the send job produced no outcome")
            }
            return outcome
        }
    }

    private func makeClock() -> TestClock { TestClock(from: startDate) }

    private func readyConfiguration(kind: AnalysisAgentKind = .codex) -> StaticConfiguration {
        StaticConfiguration(configuration: .ready(agentKind: kind, selectedModel: nil))
    }

    private func makeService(
        _ persistence: PersistenceController,
        agent: FakeConversationAgent,
        configuration: ConversationConfigurationProviding? = nil,
        clock: TestClock? = nil
    ) throws -> ConversationService {
        try ConversationService(
            persistence: persistence,
            contextProvider: RetrievalConversationContextProvider(persistence: persistence),
            responder: agent,
            configuration: configuration ?? readyConfiguration(),
            now: { clock?.tick() ?? startDate },
            makeID: { UUID().uuidString }
        )
    }

    private func readConversationsFromDisk(_ directory: URL) throws -> [StoredConversation] {
        try PersistenceController(directory: directory).loadConversations()
    }

    private func waitForCallCount(_ agent: FakeConversationAgent, _ count: Int, timeout: TimeInterval = 10) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if agent.callCount >= count { return }
            Thread.sleep(forTimeInterval: 0.01)
        }
        throw TestFailure("the fake agent did not receive \(count) invocation(s) in time")
    }

    private func setDirectoryWritable(_ directory: URL, _ writable: Bool) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: writable ? 0o755 : 0o555],
            ofItemAtPath: directory.path
        )
    }

    private func userMessage(in stored: [StoredConversation], conversationID: String) throws -> ConversationMessage {
        let conversation = try require(stored.first { $0.record.id == conversationID })
        return try require(conversation.messages.last { $0.speaker == .user }, "expected a durable user message")
    }

    private func assistantMessages(in stored: [StoredConversation], conversationID: String) -> [ConversationMessage] {
        stored.first { $0.record.id == conversationID }?.messages.filter { $0.speaker == .assistant } ?? []
    }

    // MARK: Synthetic session fixtures (for approved-context continuity)

    private func makeSession(id: String, turnID: String, text: String, at: Date) -> WorkSession {
        let revision = TurnRevision(
            revisionID: "rev-\(turnID)",
            importedAt: startDate,
            timestamp: at,
            timestampApproximate: false,
            retainedText: text,
            retainedTextTruncated: false,
            localPreview: String(text.prefix(20)),
            previewTruncated: text.count > 20
        )
        let turn = ConversationTurn(
            id: turnID,
            sessionID: id,
            role: .user,
            sourceTurnID: nil,
            sourcePath: "/tmp/synthetic/fixture-source.jsonl",
            sourceLine: 2,
            sequence: 0,
            observedAttribution: .unclear,
            observedAttributionNote: "Observed role in synthetic fixture",
            revisions: [revision]
        )
        return WorkSession(
            id: id,
            sourceKind: .codex,
            sourceSessionID: "source-\(id)",
            title: nil,
            project: nil,
            importRevision: 1,
            firstImportedAt: startDate,
            lastImportedAt: startDate,
            startedAt: at,
            startedAtApproximate: false,
            lastActivityAt: at,
            turns: [turn],
            coverage: CoverageSummary(
                turnCount: 1,
                approximateTimestampTurnCount: 0,
                truncatedRetainedTextTurnCount: 0,
                missingSessionIdentity: false,
                firstRecordedAt: at,
                lastRecordedAt: at,
                parserVersion: "codex-sessions/1",
                parserUncertaintyNotes: []
            )
        )
    }

    private func writeSourceFixture(at url: URL) {
        let lines = [
            #"{"timestamp":"2026-01-05T09:00:00Z","type":"session_meta","payload":{"id":"fixture-source"}}"#,
            #"{"timestamp":"2026-01-05T09:00:05Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Synthetic source text about debugging stored only for import."}]}}"#
        ]
        Fixtures.write(lines.joined(separator: "\n") + "\n", to: url)
    }

    // MARK: Tests

    func firstMessageIsPersistedBeforeInvocationAndResponseAfterValidation() throws {
        let directory = Fixtures.makeTempDirectory("conv-first-message")
        let persistence = PersistenceController(directory: directory)
        let clock = makeClock()
        let probe = AsyncResultBox<Bool>()
        let agent = FakeConversationAgent(onInvoke: { _, _ in
            // Snapshot the durable store at invocation time with a fresh
            // reader: the submitted user message must already be on disk.
            Task.detached {
                let present = ((try? PersistenceController(directory: directory).loadConversations()) ?? [])
                    .contains { stored in stored.messages.contains { $0.speaker == .user } }
                probe.fulfill(present)
            }
        })
        let service = try makeService(persistence, agent: agent, clock: clock)
        let conversation = try awaitAsyncThrows { try await service.createConversation() }

        let outcome = try awaitAsyncThrows { await service.send("How is my debugging progressing?", in: conversation.id) }
        guard case .accepted(let requestID) = outcome else {
            throw TestFailure("expected an accepted send, got \(outcome)")
        }

        var persistedBeforeInvocation = probe.take()
        let probeDeadline = Date().addingTimeInterval(5)
        while persistedBeforeInvocation == nil && Date() < probeDeadline {
            Thread.sleep(forTimeInterval: 0.01)
            persistedBeforeInvocation = probe.take()
        }
        guard let persistedBeforeInvocation else {
            throw TestFailure("the invocation probe never ran")
        }
        try expectTrue(persistedBeforeInvocation, "the user message must be durably saved before the agent is invoked")

        let onDisk = try readConversationsFromDisk(directory)
        try expectEqual(onDisk.count, 1)
        let savedUser = try userMessage(in: onDisk, conversationID: conversation.id)
        try expectEqual(savedUser.text, "How is my debugging progressing?")
        try expectEqual(savedUser.requestID, requestID)
        try expectEqual(savedUser.transmission, ConversationTransmission.sent)

        let state = try require(awaitAsyncThrows { await service.requestState(requestID) })
        guard case .completed(let responseMessageID) = state.phase else {
            throw TestFailure("expected a completed request, got \(state.phase)")
        }
        try expectEqual(state.transmission, ConversationTransmission.sent)
        let responses = assistantMessages(in: onDisk, conversationID: conversation.id)
        try expectEqual(responses.count, 1)
        try expectEqual(responses[0].id, responseMessageID)
        try expectEqual(responses[0].requestID, requestID)
        try expectTrue(responses[0].text.contains("How is my debugging progressing?"))
        try expectNil(responses[0].usage, "the current transport reports no usage; it must stay unknown")
    }

    func followUpContinuityUsesDurableConversationWithoutSourceReads() throws {
        let directory = Fixtures.makeTempDirectory("conv-followup")
        let persistence = PersistenceController(directory: directory)
        let sourceFixture = directory.appendingPathComponent("fixture-source.jsonl")
        writeSourceFixture(at: sourceFixture)
        try persistence.saveSessions([
            makeSession(
                id: "fixture-debug-session",
                turnID: "fixture-debug-turn-1",
                text: "Synthetic retained turn about debugging hypotheses and verification steps.",
                at: startDate.addingTimeInterval(-3_600)
            )
        ])

        let agent = FakeConversationAgent()
        let service = try makeService(persistence, agent: agent)
        let conversation = try awaitAsyncThrows { try await service.createConversation() }

        _ = try awaitAsyncThrows { await service.send("How is my debugging progressing?", in: conversation.id) }
        try expectEqual(agent.callCount, 1)
        try expectTrue(agent.calls[0].request.followUpTurns.isEmpty, "the first message has no prior durable exchange")

        // The approved-context envelope comes from the owned sessions store.
        try expectTrue(agent.calls[0].context.items.contains { $0.id == "fixture-debug-turn-1" })

        // The source fixture is gone from disk; the durable conversation and
        // the owned store are the only bases for the follow-up.
        try FileManager.default.removeItem(at: sourceFixture)

        _ = try awaitAsyncThrows { await service.send("What did that debugging review teach me?", in: conversation.id) }
        try expectEqual(agent.callCount, 2)

        let followUps = agent.calls[1].request.followUpTurns
        try expectEqual(followUps.count, 2, "the durable first exchange must travel with the follow-up")
        try expectEqual(followUps[0].speaker, ConversationSpeaker.user)
        try expectEqual(followUps[0].text, "How is my debugging progressing?")
        try expectEqual(followUps[1].speaker, ConversationSpeaker.assistant)
        try expectTrue(followUps[1].text.contains("How is my debugging progressing?"), "the fake answer quotes the question; it must come from the durable conversation")

        // Retrieval still serves stored content; nothing from the deleted
        // source file path is involved, and the store-only turn is intact.
        try expectTrue(agent.calls[1].context.items.contains { $0.id == "fixture-debug-turn-1" })
        try expectTrue(agent.calls[1].request.followUpTurns.allSatisfy { !$0.text.contains("stored only for import") })
    }

    func invalidResponseReferencesAndMalformedOutputAreRejectedWithoutSavedClaims() throws {
        let directory = Fixtures.makeTempDirectory("conv-invalid-response")
        let persistence = PersistenceController(directory: directory)
        try persistence.saveSessions([
            makeSession(id: "fixture-session", turnID: "fixture-turn-known", text: "Synthetic turn about debugging verification.", at: startDate)
        ])
        let observationHashesBefore = try observationStoreHashes(directory)

        let agent = FakeConversationAgent(behaviors: [
            .answer(text: "Cites an unknown context item.", references: ["fixture-turn-unknown"]),
            .answer(text: "   \n  ")
        ])
        let service = try makeService(persistence, agent: agent)
        let conversation = try awaitAsyncThrows { try await service.createConversation() }

        let first = try awaitAsyncThrows { await service.send("What does my debugging work show?", in: conversation.id) }
        guard case .accepted(let firstRequestID) = first else { throw TestFailure("expected acceptance") }
        let state = try require(awaitAsyncThrows { await service.requestState(firstRequestID) })
        guard case .invalidResponse(let note) = state.phase else {
            throw TestFailure("expected an invalid-response outcome, got \(state.phase)")
        }
        try expectTrue(note.contains("were not part of this request's context"), "the note must explain the reference rejection")
        try expectEqual(state.transmission, ConversationTransmission.sent, "the call completed, so the request was sent")

        let second = try awaitAsyncThrows { await service.send("And my verification habits?", in: conversation.id) }
        guard case .accepted(let secondRequestID) = second else { throw TestFailure("expected acceptance") }
        let secondState = try require(awaitAsyncThrows { await service.requestState(secondRequestID) })
        guard case .invalidResponse = secondState.phase else {
            throw TestFailure("expected an invalid-response outcome for empty output, got \(secondState.phase)")
        }

        let onDisk = try readConversationsFromDisk(directory)
        try expectEqual(assistantMessages(in: onDisk, conversationID: conversation.id).count, 0, "a rejected response must never become a durable message")
        try expectEqual(try observationStoreHashes(directory), observationHashesBefore, "conversation activity must never mutate observation stores")

        // A response citing a genuinely included item validates and persists.
        let knownEnvelopeItemID = agent.calls[0].context.items.first?.id
        let agent2 = FakeConversationAgent(behaviors: [
            .answer(text: "Grounded answer.", references: knownEnvelopeItemID.map { [$0] } ?? [])
        ])
        let service2 = try makeService(persistence, agent: agent2)
        _ = try awaitAsyncThrows { await service2.send("Ground this debugging answer for me.", in: conversation.id) }
        let after = try readConversationsFromDisk(directory)
        try expectEqual(assistantMessages(in: after, conversationID: conversation.id).count, 1, "a valid response with a known reference is saved")
    }

    func failedUserMessageSaveReturnsUnsentTextAndNeverInvokes() throws {
        let directory = Fixtures.makeTempDirectory("conv-user-save-failure")
        let persistence = PersistenceController(directory: directory)
        let agent = FakeConversationAgent()
        let service = try makeService(persistence, agent: agent)
        let conversation = try awaitAsyncThrows { try await service.createConversation() }

        try setDirectoryWritable(directory, false)
        let outcome = try awaitAsyncThrows { await service.send("Unsent because the disk refused the write.", in: conversation.id) }
        guard case .saveFailed(let unsent) = outcome else {
            throw TestFailure("expected a save failure, got \(outcome)")
        }
        try expectEqual(unsent, "Unsent because the disk refused the write.")
        try expectEqual(agent.callCount, 0, "nothing may be invoked when the user message could not be saved")

        let onDisk = try readConversationsFromDisk(directory)
        try expectEqual(try require(onDisk.first { $0.record.id == conversation.id }).messages.count, 0, "no fake saved message may exist")

        try setDirectoryWritable(directory, true)
        let retry = try awaitAsyncThrows { await service.send("Unsent because the disk refused the write.", in: conversation.id) }
        guard case .accepted = retry else { throw TestFailure("expected the retry send to be accepted") }
        try expectEqual(agent.callCount, 1)
        let after = try readConversationsFromDisk(directory)
        try expectEqual(try require(after.first { $0.record.id == conversation.id }).messages.count, 2, "the retried send persists its user message and the response")
    }

    func failedResponseSaveRetainsResponseAndRetryDoesNotReinvoke() throws {
        let directory = Fixtures.makeTempDirectory("conv-response-save-failure")
        let persistence = PersistenceController(directory: directory)
        let gate = Gate()
        let answerText = "A generated response that failed to save once."
        let agent = FakeConversationAgent(behaviors: [.gated(gate, text: answerText, references: [], ignoresCancellation: false)])
        let service = try makeService(persistence, agent: agent)
        let conversation = try awaitAsyncThrows { try await service.createConversation() }

        let job = SendJob(service, "Please answer with persistence problems.", conversationID: conversation.id)
        try waitForCallCount(agent, 1)
        try setDirectoryWritable(directory, false)
        gate.open()
        _ = try job.awaitResult()

        var state = try require(awaitAsyncThrows { await service.requestState(try requireFirst(agentCallRequestID(agent))) })
        guard case .responseSaveFailed(let note) = state.phase else {
            throw TestFailure("expected a response-save-failed outcome, got \(state.phase)")
        }
        try expectTrue(note.contains("could not be saved"), "the note must be honest about the failed write")
        try expectTrue(state.retryAvailable, "the generated response must be retained for retry")
        try expectEqual(state.transmission, ConversationTransmission.sent, "the call completed, so the request was sent")

        let onDisk = try readConversationsFromDisk(directory)
        try expectEqual(assistantMessages(in: onDisk, conversationID: conversation.id).count, 0, "the unsaved response must not appear durable")

        try setDirectoryWritable(directory, true)
        let retry = try awaitAsyncThrows { await service.retryUnsavedResponse(in: conversation.id) }
        guard case .persisted = retry else { throw TestFailure("expected the response retry to persist, got \(retry)") }
        try expectEqual(agent.callCount, 1, "retrying the save must never contact the agent again")

        let after = try readConversationsFromDisk(directory)
        let responses = assistantMessages(in: after, conversationID: conversation.id)
        try expectEqual(responses.count, 1)
        try expectEqual(responses[0].text, answerText, "the persisted response is exactly the retained one")
        state = try require(awaitAsyncThrows { await service.requestState(try requireFirst(agentCallRequestID(agent))) })
        guard case .completed = state.phase else { throw TestFailure("expected a completed outcome after retry") }
    }

    func stopDuringRunCancelsAndSuppressesLateCompletion() throws {
        let directory = Fixtures.makeTempDirectory("conv-stop-late")
        let persistence = PersistenceController(directory: directory)
        let gate = Gate()
        let agent = FakeConversationAgent(behaviors: [
            .gated(gate, text: "A completion that arrives after the stop.", references: [], ignoresCancellation: true)
        ])
        let service = try makeService(persistence, agent: agent)
        let conversation = try awaitAsyncThrows { try await service.createConversation() }

        let job = SendJob(service, "Answer slowly.", conversationID: conversation.id)
        try waitForCallCount(agent, 1)
        let requestID = try requireFirst(agentCallRequestID(agent))
        try awaitAsyncThrows { await service.stop(requestID: requestID) }

        let stopped = try require(awaitAsyncThrows { await service.requestState(requestID) })
        guard case .canceled = stopped.phase else { throw TestFailure("expected a canceled outcome, got \(stopped.phase)") }
        try expectEqual(stopped.transmission, ConversationTransmission.possiblySent, "a stopped run may already have transmitted; unknown stays unknown, not none")

        gate.open()
        _ = try job.awaitResult()

        let after = try require(awaitAsyncThrows { await service.requestState(requestID) })
        guard case .canceled = after.phase else { throw TestFailure("the late completion must not change the canceled outcome") }
        let onDisk = try readConversationsFromDisk(directory)
        try expectEqual(assistantMessages(in: onDisk, conversationID: conversation.id).count, 0, "a late completion after stop must never be persisted")
        let retry = try awaitAsyncThrows { await service.retryUnsavedResponse(in: conversation.id) }
        guard case .noRetainedResponse = retry else { throw TestFailure("a suppressed late response must not be retained for retry") }
    }

    func outOfOrderCompletionIsolatesEachConversation() throws {
        let directory = Fixtures.makeTempDirectory("conv-out-of-order")
        let persistence = PersistenceController(directory: directory)
        let gateA = Gate()
        let gateB = Gate()
        let answerA = "Slow answer for conversation A."
        let answerB = "Fast answer for conversation B."
        let agent = FakeConversationAgent(behaviors: [
            .gated(gateA, text: answerA, references: [], ignoresCancellation: false),
            .gated(gateB, text: answerB, references: [], ignoresCancellation: false)
        ])
        let service = try makeService(persistence, agent: agent)
        let conversationA = try awaitAsyncThrows { try await service.createConversation() }
        let conversationB = try awaitAsyncThrows { try await service.createConversation() }

        let jobA = SendJob(service, "Question for A about debugging.", conversationID: conversationA.id)
        try waitForCallCount(agent, 1)
        try expectTrue(agent.calls[0].request.conversationID == conversationA.id, "the first invocation must belong to A")
        let jobB = SendJob(service, "Question for B about design.", conversationID: conversationB.id)
        try waitForCallCount(agent, 2)
        try expectTrue(agent.calls[1].request.conversationID == conversationB.id)

        // B completes first; A is still running.
        gateB.open()
        _ = try jobB.awaitResult()
        let requestA = try requireFirst(agentCallRequestID(agent, at: 0))
        let runningA = try require(awaitAsyncThrows { await service.requestState(requestA) })
        guard case .running = runningA.phase else { throw TestFailure("A must still be running while B completed") }

        gateA.open()
        _ = try jobA.awaitResult()

        let onDisk = try readConversationsFromDisk(directory)
        let responsesA = assistantMessages(in: onDisk, conversationID: conversationA.id)
        let responsesB = assistantMessages(in: onDisk, conversationID: conversationB.id)
        try expectEqual(responsesA.count, 1)
        try expectEqual(responsesB.count, 1)
        try expectEqual(responsesA[0].text, answerA, "each response must land in its own conversation")
        try expectEqual(responsesB[0].text, answerB)
        try expectTrue(onDisk.allSatisfy { stored in
            stored.messages.allSatisfy { $0.conversationID == stored.record.id }
        }, "no message may cross conversations")
    }

    func switchingConversationsDuringRunKeepsStateIsolated() throws {
        let directory = Fixtures.makeTempDirectory("conv-switch")
        let persistence = PersistenceController(directory: directory)
        let gate = Gate()
        let agent = FakeConversationAgent(behaviors: [
            .gated(gate, text: "Answer that belongs to conversation A.", references: [], ignoresCancellation: false)
        ])
        let service = try makeService(persistence, agent: agent)
        let conversationA = try awaitAsyncThrows { try await service.createConversation() }
        let conversationB = try awaitAsyncThrows { try await service.createConversation() }

        let job = SendJob(service, "Question for A only.", conversationID: conversationA.id)
        try waitForCallCount(agent, 1)

        // While A's run is in flight, the user switches: creates a new
        // conversation, drafts in B, and reads B. None of these operations
        // may invoke or mutate A's run.
        _ = try awaitAsyncThrows { try await service.createConversation() }
        try awaitAsyncThrows { try await service.setDraft("Draft written while A runs.", for: conversationB.id) }
        _ = try awaitAsyncThrows { await service.messages(in: conversationB.id) }

        gate.open()
        _ = try job.awaitResult()

        let onDisk = try readConversationsFromDisk(directory)
        try expectEqual(assistantMessages(in: onDisk, conversationID: conversationA.id).count, 1)
        try expectEqual(assistantMessages(in: onDisk, conversationID: conversationB.id).count, 0, "A's response must never appear in B")
        let draft = try require(onDisk.first { $0.record.id == conversationB.id }).record.draftText
        try expectEqual(draft, "Draft written while A runs.")
        try expectEqual(onDisk.count, 3, "the created conversation must exist exactly once")
    }

    func relaunchRestoresConversationsMessagesAndDraftsWithoutInvocation() throws {
        let directory = Fixtures.makeTempDirectory("conv-relaunch")
        let persistence = PersistenceController(directory: directory)
        let agent1 = FakeConversationAgent()
        let service1 = try makeService(persistence, agent: agent1, clock: makeClock())
        let conversation = try awaitAsyncThrows { try await service1.createConversation() }
        _ = try awaitAsyncThrows { await service1.send("First durable question about debugging.", in: conversation.id) }
        try awaitAsyncThrows { try await service1.setDraft("Draft text that must survive a relaunch.", for: conversation.id) }

        // A fresh service over the same store directory simulates relaunch.
        let agent2 = FakeConversationAgent()
        let service2 = try makeService(persistence, agent: agent2, clock: makeClock())
        let restored = try awaitAsyncThrows { await service2.conversations() }
        try expectEqual(restored.count, 1)
        try expectEqual(restored[0].id, conversation.id)
        try expectEqual(restored[0].draftText, "Draft text that must survive a relaunch.")
        let restoredMessages = try awaitAsyncThrows { await service2.messages(in: conversation.id) }
        try expectEqual(restoredMessages.count, 2)
        try expectEqual(restoredMessages[0].speaker, ConversationSpeaker.user)
        try expectEqual(restoredMessages[0].text, "First durable question about debugging.")
        try expectEqual(restoredMessages[1].speaker, ConversationSpeaker.assistant)
        try expectEqual(agent2.callCount, 0, "restoring a conversation must never invoke the agent")

        // The restored conversation accepts a follow-up with full continuity.
        _ = try awaitAsyncThrows { await service2.send("Follow-up after relaunch.", in: conversation.id) }
        try expectEqual(agent2.callCount, 1)
        let followUps = agent2.calls[0].request.followUpTurns
        try expectTrue(followUps.contains { $0.text == "First durable question about debugging." }, "relaunched continuity must come from the durable store")
    }

    func relaunchWithOpenRequestReportsInterruptedAndUnknownTransmission() throws {
        let directory = Fixtures.makeTempDirectory("conv-relaunch-interrupted")
        let persistence = PersistenceController(directory: directory)
        let agent1 = FakeConversationAgent(behaviors: [.parkedUntilCanceled])
        let service1 = try makeService(persistence, agent: agent1)
        let conversation = try awaitAsyncThrows { try await service1.createConversation() }

        let job = SendJob(service1, "This run will be interrupted.", conversationID: conversation.id)
        try waitForCallCount(agent1, 1)
        let requestID = try requireFirst(agentCallRequestID(agent1))

        // A fresh service sees exactly the durable truth: a saved user
        // message with no recorded outcome.
        let service2 = try makeService(persistence, agent: FakeConversationAgent())
        let state = try require(awaitAsyncThrows { await service2.requestState(requestID) })
        guard case .interrupted = state.phase else { throw TestFailure("expected an interrupted request, got \(state.phase)") }
        try expectEqual(state.transmission, ConversationTransmission.unknown, "an interrupted request's transmission stays unknown")
        let onDisk = try readConversationsFromDisk(directory)
        try expectEqual(assistantMessages(in: onDisk, conversationID: conversation.id).count, 0, "no response may appear for an interrupted request")

        // Cleanup: resolve the parked run of the first service explicitly.
        try awaitAsyncThrows { await service1.stop(requestID: requestID) }
        _ = try job.awaitResult()
    }

    func configurationUnavailableBlocksWithClearReasonAndNoInvocation() throws {
        let directory = Fixtures.makeTempDirectory("conv-config-unavailable")
        let persistence = PersistenceController(directory: directory)
        let agent = FakeConversationAgent()
        var settings = AppSettings.default()
        let disabledProvider = SettingsConversationConfigurationProvider { settings }
        let service = try makeService(persistence, agent: agent, configuration: disabledProvider)
        let conversation = try awaitAsyncThrows { try await service.createConversation() }

        let disabled = try awaitAsyncThrows { await service.send("This must not run while disabled.", in: conversation.id) }
        try expectEqual(disabled, .configurationUnavailable(reason: "AI conversation is turned off in Settings."))
        try expectEqual(agent.callCount, 0)
        try expectEqual(try readConversationsFromDisk(directory).first { $0.record.id == conversation.id }?.messages.count, 0, "a blocked send saves no message")

        settings.aiEnabled = true
        settings.analysisAgent = nil
        let missingAgent = try awaitAsyncThrows { await service.send("No agent selected.", in: conversation.id) }
        try expectEqual(missingAgent, .configurationUnavailable(reason: "Choose a supported analysis agent in Settings to start a conversation."))
        try expectEqual(agent.callCount, 0)

        settings.analysisAgent = .codex
        let ready = try awaitAsyncThrows { await service.send("Now it is configured.", in: conversation.id) }
        guard case .accepted = ready else { throw TestFailure("a ready configuration must accept the send") }
        try expectEqual(agent.callCount, 1)
    }

    func emptyMessageAndUnknownConversationAreRejectedWithoutWrites() throws {
        let directory = Fixtures.makeTempDirectory("conv-rejected-inputs")
        let persistence = PersistenceController(directory: directory)
        let agent = FakeConversationAgent()
        let service = try makeService(persistence, agent: agent)
        let conversation = try awaitAsyncThrows { try await service.createConversation() }
        let storeURL = directory.appendingPathComponent("conversations.json")
        let before = try? Data(contentsOf: storeURL)

        try expectEqual(
            awaitAsyncThrows { await service.send("   \n\t ", in: conversation.id) },
            ConversationSendOutcome.emptyMessage
        )
        try expectEqual(
            awaitAsyncThrows { await service.send("Text for a conversation that does not exist.", in: "missing-conversation") },
            ConversationSendOutcome.conversationNotFound
        )
        try expectEqual(agent.callCount, 0)
        let after = try? Data(contentsOf: storeURL)
        try expectEqual(after, before, "rejected sends must not write the store")
    }

    func secondSendWhileRunIsActiveIsRefusedWithoutInvocation() throws {
        let directory = Fixtures.makeTempDirectory("conv-run-active")
        let persistence = PersistenceController(directory: directory)
        let gate = Gate()
        let agent = FakeConversationAgent(behaviors: [
            .gated(gate, text: "The only in-flight answer.", references: [], ignoresCancellation: false)
        ])
        let service = try makeService(persistence, agent: agent)
        let conversation = try awaitAsyncThrows { try await service.createConversation() }

        let job = SendJob(service, "First message, still running.", conversationID: conversation.id)
        try waitForCallCount(agent, 1)
        try expectEqual(
            awaitAsyncThrows { await service.send("Second message while the first runs.", in: conversation.id) },
            ConversationSendOutcome.runAlreadyActive
        )
        try expectEqual(agent.callCount, 1, "the refused send must not invoke")

        let requestID = try requireFirst(agentCallRequestID(agent))
        try awaitAsyncThrows { await service.stop(requestID: requestID) }
        gate.open()
        _ = try job.awaitResult()
    }

    func contextBuildFailureFailsRunBeforeInvocationWithNoTransmission() throws {
        let directory = Fixtures.makeTempDirectory("conv-context-failure")
        let persistence = PersistenceController(directory: directory)
        let agent = FakeConversationAgent()
        let clock = makeClock()
        let service = try ConversationService(
            persistence: persistence,
            contextProvider: ThrowingContextProvider(),
            responder: agent,
            configuration: readyConfiguration(),
            now: { clock.tick() },
            makeID: { UUID().uuidString }
        )
        let conversation = try awaitAsyncThrows { try await service.createConversation() }

        let outcome = try awaitAsyncThrows { await service.send("This question cannot build context.", in: conversation.id) }
        guard case .accepted(let requestID) = outcome else { throw TestFailure("the user message was saved, so the send is accepted") }
        try expectEqual(agent.callCount, 0, "a context failure must happen before any invocation")

        let state = try require(awaitAsyncThrows { await service.requestState(requestID) })
        guard case .failed(let note) = state.phase else { throw TestFailure("expected a failed outcome, got \(state.phase)") }
        try expectTrue(note.contains("was not sent"), "the failure must state that nothing was sent")
        try expectEqual(state.transmission, ConversationTransmission.none, "nothing was invoked, so transmission is definitively none")

        let onDisk = try readConversationsFromDisk(directory)
        let saved = try userMessage(in: onDisk, conversationID: conversation.id)
        try expectEqual(saved.transmission, ConversationTransmission.none)
    }

    func noOperationUntilExplicitInvocation() throws {
        let directory = Fixtures.makeTempDirectory("conv-no-implicit-operation")
        let persistence = PersistenceController(directory: directory)
        let agent = FakeConversationAgent()
        let service = try makeService(persistence, agent: agent)
        try expectEqual(agent.callCount, 0, "initializing must not invoke")

        let conversation = try awaitAsyncThrows { try await service.createConversation() }
        try awaitAsyncThrows { try await service.setDraft("Just drafting, nothing sent.", for: conversation.id) }
        _ = try awaitAsyncThrows { await service.conversations() }
        _ = try awaitAsyncThrows { await service.messages(in: conversation.id) }
        _ = try awaitAsyncThrows { await service.requestState("no-such-request") }
        try expectEqual(agent.callCount, 0, "reading, creating, and drafting must never invoke")

        let reloaded = try makeService(persistence, agent: agent)
        _ = try awaitAsyncThrows { await reloaded.conversations() }
        _ = try awaitAsyncThrows { await reloaded.messages(in: conversation.id) }
        try expectEqual(agent.callCount, 0, "relaunching must never invoke")

        let messages = try readConversationsFromDisk(directory).first { $0.record.id == conversation.id }?.messages
        try expectEqual(messages?.count, 0, "no message may exist without an explicit send")
    }

    func transmissionAndCostStatesRemainTruthfullyUnknown() throws {
        let directory = Fixtures.makeTempDirectory("conv-truthful-usage")
        let persistence = PersistenceController(directory: directory)
        // The current transport reports no usage figures at all.
        let agent = FakeConversationAgent(behaviors: [
            .answer(text: "Answer with no usage reported.")
        ])
        let service = try makeService(persistence, agent: agent)
        let conversation = try awaitAsyncThrows { try await service.createConversation() }

        _ = try awaitAsyncThrows { await service.send("Any usage facts?", in: conversation.id) }
        let onDisk = try readConversationsFromDisk(directory)
        let response = try require(assistantMessages(in: onDisk, conversationID: conversation.id).first)
        try expectNil(response.usage, "unknown usage must be represented by absence, never by zeros")
        try expectEqual(response.transmission, ConversationTransmission.sent)
        try expectNil(response.selectedModel, "no provider-reported model exists in this slice")
        try expectEqual(response.agentKind, AnalysisAgentKind.codex, "the locally selected agent is recorded from the configuration snapshot")
    }

    func responseValidatorRejectsUnknownReferencesMismatchedRequestsAndEmptyText() throws {
        let directory = Fixtures.makeTempDirectory("conv-validator")
        let persistence = PersistenceController(directory: directory)
        try persistence.saveSessions([
            makeSession(id: "fixture-session", turnID: "fixture-turn-1", text: "Synthetic turn about debugging.", at: startDate)
        ])
        let retriever = ContextRetriever(persistence: persistence)
        let envelope = try retriever.retrieve(ContextRetrievalRequest(terms: ["debugging"]), now: startDate)
        let includedID = try require(envelope.items.first?.id, "the fixture session must be included in the envelope")

        do {
            try ResponseValidator.validate(
                FakeConversationAgent.response(requestID: "request-1", text: "Grounded.", references: [includedID]),
                expectedRequestID: "request-1",
                envelope: envelope
            )
        } catch {
            throw TestFailure("a grounded response with known references must validate")
        }

        do {
            try ResponseValidator.validate(FakeConversationAgent.response(requestID: "request-1", text: "Cites air.", references: ["not-in-envelope"]), expectedRequestID: "request-1", envelope: envelope)
            throw TestFailure("unknown references must be rejected")
        } catch let rejection as ResponseValidationRejection {
            guard case .unknownReferences = rejection else { throw TestFailure("expected unknownReferences, got \(rejection)") }
        }

        do {
            try ResponseValidator.validate(FakeConversationAgent.response(requestID: "other-request", text: "Fine text."), expectedRequestID: "request-1", envelope: envelope)
            throw TestFailure("a mismatched request ID must be rejected")
        } catch let rejection as ResponseValidationRejection {
            guard case .requestMismatch = rejection else { throw TestFailure("expected requestMismatch, got \(rejection)") }
        }

        do {
            try ResponseValidator.validate(FakeConversationAgent.response(requestID: "request-1", text: "  "), expectedRequestID: "request-1", envelope: envelope)
            throw TestFailure("empty answer text must be rejected")
        } catch let rejection as ResponseValidationRejection {
            guard case .emptyAnswer = rejection else { throw TestFailure("expected emptyAnswer, got \(rejection)") }
        }
    }

    // MARK: Small helpers

    private func agentCallRequestID(_ agent: FakeConversationAgent, at index: Int = 0) -> String? {
        let calls = agent.calls
        guard calls.indices.contains(index) else { return nil }
        return calls[index].request.id
    }

    private func requireFirst(_ value: String?) throws -> String {
        try require(value, "expected a recorded fake-agent call")
    }

    /// Hashes every observation store file that exists. Conversation
    /// activity must leave all of them byte-identical.
    private func observationStoreHashes(_ directory: URL) throws -> [String: String] {
        var hashes: [String: String] = [:]
        for name in ["events.json", "corrections.json", "reports.json", "sessions.json", "manifests.json", "settings.json"] {
            let url = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            hashes[name] = StoreFileHashing.sha256Hex(try Data(contentsOf: url))
        }
        return hashes
    }

    static var entries: [TestEntry] {
        let tests = ConversationServiceTests()
        return [
            TestEntry(suite: suiteName, name: "firstMessageIsPersistedBeforeInvocationAndResponseAfterValidation") {
                try tests.firstMessageIsPersistedBeforeInvocationAndResponseAfterValidation()
            },
            TestEntry(suite: suiteName, name: "followUpContinuityUsesDurableConversationWithoutSourceReads") {
                try tests.followUpContinuityUsesDurableConversationWithoutSourceReads()
            },
            TestEntry(suite: suiteName, name: "invalidResponseReferencesAndMalformedOutputAreRejectedWithoutSavedClaims") {
                try tests.invalidResponseReferencesAndMalformedOutputAreRejectedWithoutSavedClaims()
            },
            TestEntry(suite: suiteName, name: "failedUserMessageSaveReturnsUnsentTextAndNeverInvokes") {
                try tests.failedUserMessageSaveReturnsUnsentTextAndNeverInvokes()
            },
            TestEntry(suite: suiteName, name: "failedResponseSaveRetainsResponseAndRetryDoesNotReinvoke") {
                try tests.failedResponseSaveRetainsResponseAndRetryDoesNotReinvoke()
            },
            TestEntry(suite: suiteName, name: "stopDuringRunCancelsAndSuppressesLateCompletion") {
                try tests.stopDuringRunCancelsAndSuppressesLateCompletion()
            },
            TestEntry(suite: suiteName, name: "outOfOrderCompletionIsolatesEachConversation") {
                try tests.outOfOrderCompletionIsolatesEachConversation()
            },
            TestEntry(suite: suiteName, name: "switchingConversationsDuringRunKeepsStateIsolated") {
                try tests.switchingConversationsDuringRunKeepsStateIsolated()
            },
            TestEntry(suite: suiteName, name: "relaunchRestoresConversationsMessagesAndDraftsWithoutInvocation") {
                try tests.relaunchRestoresConversationsMessagesAndDraftsWithoutInvocation()
            },
            TestEntry(suite: suiteName, name: "relaunchWithOpenRequestReportsInterruptedAndUnknownTransmission") {
                try tests.relaunchWithOpenRequestReportsInterruptedAndUnknownTransmission()
            },
            TestEntry(suite: suiteName, name: "configurationUnavailableBlocksWithClearReasonAndNoInvocation") {
                try tests.configurationUnavailableBlocksWithClearReasonAndNoInvocation()
            },
            TestEntry(suite: suiteName, name: "emptyMessageAndUnknownConversationAreRejectedWithoutWrites") {
                try tests.emptyMessageAndUnknownConversationAreRejectedWithoutWrites()
            },
            TestEntry(suite: suiteName, name: "secondSendWhileRunIsActiveIsRefusedWithoutInvocation") {
                try tests.secondSendWhileRunIsActiveIsRefusedWithoutInvocation()
            },
            TestEntry(suite: suiteName, name: "contextBuildFailureFailsRunBeforeInvocationWithNoTransmission") {
                try tests.contextBuildFailureFailsRunBeforeInvocationWithNoTransmission()
            },
            TestEntry(suite: suiteName, name: "noOperationUntilExplicitInvocation") {
                try tests.noOperationUntilExplicitInvocation()
            },
            TestEntry(suite: suiteName, name: "transmissionAndCostStatesRemainTruthfullyUnknown") {
                try tests.transmissionAndCostStatesRemainTruthfullyUnknown()
            },
            TestEntry(suite: suiteName, name: "responseValidatorRejectsUnknownReferencesMismatchedRequestsAndEmptyText") {
                try tests.responseValidatorRejectsUnknownReferencesMismatchedRequestsAndEmptyText()
            }
        ]
    }
}
