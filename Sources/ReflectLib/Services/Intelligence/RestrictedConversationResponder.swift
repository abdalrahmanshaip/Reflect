import Foundation

/// Safe, typed failures for `RestrictedConversationResponder`. Every message
/// is generic English: raw agent stdout/stderr, exit codes, payload text, and
/// any store or source locators are never quoted.
public enum RestrictedConversationResponderError: LocalizedError, Equatable {
    /// The explicitly provided executable URL did not verify as a local
    /// executable file at initialization time.
    case agentNotVerified
    /// The selected agent kind is not among the supported restricted agents.
    case unsupportedAgentKind
    /// The selected model option is not one of the agent's known options.
    case unsupportedModelOption
    /// The prompt's fixed parts alone exceed the hard stdin limit, so the
    /// request was not sent. Approved context is never truncated to fit.
    case promptTooLarge
    /// The isolated working directory could not be prepared.
    case preparationFailed
    /// The agent process could not be started or did not exit successfully.
    case invocationFailed
    /// The agent process exceeded its time limit.
    case invocationTimedOut
    /// The agent's output was unusable: empty, malformed JSON, missing or
    /// mismatched required fields, or over the output size limit.
    case invalidOutput

    public var errorDescription: String? {
        switch self {
        case .agentNotVerified:
            return "The selected agent executable could not be verified, so the request was not sent."
        case .unsupportedAgentKind:
            return "The selected agent is not supported for conversation requests."
        case .unsupportedModelOption:
            return "The selected model option is not supported by the selected agent."
        case .promptTooLarge:
            return "The conversation request exceeded the local prompt size limit, so it was not sent."
        case .preparationFailed:
            return "The local agent request could not be prepared, so it was not sent."
        case .invocationFailed:
            return "The local agent request could not be completed. Whether anything reached the provider is unknown."
        case .invocationTimedOut:
            return "The local agent request timed out before it completed."
        case .invalidOutput:
            return "The agent returned an unusable reply, so nothing was saved."
        }
    }
}

/// A `ConversationResponding` backed by the existing restricted local CLI
/// facilities: `AnalysisProcessRunner`'s invocation contract and
/// `AnalysisProcessEnvironment`'s sanitized environment. One explicitly
/// selected, locally verified agent executable runs with the agent kind's
/// documented restricted arguments — the responder never searches PATH,
/// never reads or writes credentials, and never touches source histories or
/// the private store.
///
/// Prompt boundary, by construction: the prompt contains only the current
/// request's question, its request and conversation IDs (app-owned UUID
/// strings), the already-bounded context document rendered by the existing
/// `ContextSerializer`, and the request's durable follow-up turns. The
/// serializer's construction guarantees the context document carries no
/// source paths, line locators, or store locations, and nothing else in the
/// prompt can introduce them.
///
/// Size boundary: total stdin is enforced at 64 KiB UTF-8. When the durable
/// follow-up turns do not fit, the oldest side of the history is reduced
/// first and every cut or omission is declared in the prompt itself with a
/// count — never silent. If the fixed parts alone exceed the limit, the
/// request fails with `.promptTooLarge` instead of truncating approved
/// context.
///
/// Output boundary: the agent must answer with exactly one strict JSON
/// object carrying exactly the three top-level keys `requestID`,
/// `answerText`, and `referencedContextItemIDs` — unknown keys are rejected
/// before decoding. Empty, malformed, request-mismatched, or oversize
/// output is rejected with `.invalidOutput`; output retention keeps one
/// sentinel byte beyond the acceptable cap, so a truncated oversized reply
/// stays detectable. Reference grounding
/// against the request's actual envelope is delegated to the existing
/// `ResponseValidator`. No model identifier or usage is ever guessed: both
/// stay `nil` because this transport cannot observe them.
public struct RestrictedConversationResponder: ConversationResponding {
    /// Hard process time limit.
    private static let invocationTimeout: TimeInterval = 120
    /// Hard cap on an acceptable reply: retained stdout above this size is
    /// rejected as oversize.
    private static let maxOutputBytes = 64 * 1024
    /// Hard cap on output the runner retains (stdout and stderr each): one
    /// sentinel byte beyond the acceptable cap, so a truncated oversized
    /// reply stays detectable instead of silently passing the size check.
    private static let retainedOutputBytes = 64 * 1024 + 1
    /// Hard cap on total prompt size (UTF-8 bytes) handed to the agent.
    private static let maxStdinBytes = 64 * 1024
    /// Minimum byte room kept available for follow-up turns plus their
    /// omission markers; with turns present and less room than this, the
    /// request fails instead of degenerating.
    private static let minimumTurnAllowance = 512
    /// Marker appended when the oldest included turn was cut to fit.
    private static let cutTurnMarker = " …[this earlier turn was cut to fit the size limit]"

    private let agentKind: AnalysisAgentKind
    private let modelOptionID: String?
    private let executableURL: URL
    private let processRunner: AnalysisDiscoveryProcessRunning
    private let serializer = ContextSerializer()

    /// Creates a responder bound to one explicit, locally verified agent
    /// executable. The URL is provided by the caller (typically from an
    /// already-run availability check) and re-verified here, so the responder
    /// never resolves executables from PATH on its own.
    ///
    /// - Parameters:
    ///   - agentKind: The selected agent. Only `AnalysisAgentKind.supported`
    ///     kinds are accepted; `.copilotCLI` is rejected.
    ///   - selectedModelOptionID: The selected model option ID, or `nil` for
    ///     the agent default. A non-empty value must match one of the kind's
    ///     `modelOptions` IDs.
    ///   - executableURL: An explicit `file:` URL to the agent executable,
    ///     verified at initialization to be an existing executable file.
    ///   - processRunner: The restricted process runner to execute with.
    /// - Throws: `RestrictedConversationResponderError.agentNotVerified`,
    ///   `.unsupportedAgentKind`, or `.unsupportedModelOption`.
    ///
    /// The initializer is deliberately internal: `AnalysisDiscoveryProcessRunning` is
    /// a module-internal seam, production wiring happens in-module, and tests
    /// construct responders through `@testable` — the runner protocol is not
    /// promoted into the public API.
    init(
        agentKind: AnalysisAgentKind,
        selectedModelOptionID: String? = nil,
        executableURL: URL,
        processRunner: AnalysisDiscoveryProcessRunning
    ) throws {
        guard AnalysisAgentKind.supported.contains(agentKind) else {
            throw RestrictedConversationResponderError.unsupportedAgentKind
        }

        let trimmedModel = selectedModelOptionID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedModel, !trimmedModel.isEmpty {
            guard agentKind.modelOptions.contains(where: { $0.id == trimmedModel }) else {
                throw RestrictedConversationResponderError.unsupportedModelOption
            }
            modelOptionID = trimmedModel
        } else {
            modelOptionID = nil
        }

        guard executableURL.isFileURL,
              !executableURL.path.isEmpty,
              FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw RestrictedConversationResponderError.agentNotVerified
        }

        self.agentKind = agentKind
        self.executableURL = executableURL
        self.processRunner = processRunner
    }

    public func respond(
        to request: ConversationRequest,
        context: ContextEnvelope
    ) async throws -> ConversationResponse {
        let promptData = try Self.composePrompt(
            request: request,
            contextDocument: String(decoding: serializer.providerDocument(for: context), as: UTF8.self)
        )

        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReflectConversation-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: workingDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw RestrictedConversationResponderError.preparationFailed
        }
        // The isolated, uniquely named directory is removed on every path out
        // of this scope; the agent never shares Reflect's own directories.
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let invocation = AnalysisProcessInvocation(
            executableURL: executableURL,
            arguments: agentKind.analysisArguments(model: modelOptionID),
            input: promptData,
            workingDirectory: workingDirectory,
            environment: AnalysisProcessEnvironment.sanitized(),
            timeout: Self.invocationTimeout,
            outputLimit: Self.retainedOutputBytes
        )

        // The async runner observes the surrounding task's cancellation and
        // terminates (then escalates) the child process, so a stopped run does
        // not wait out the timeout; the 120-second invocation timeout still
        // bounds a run that is never stopped.
        let result: AnalysisProcessResult
        do {
            result = try await processRunner.run(invocation)
        } catch let processError as AnalysisProcessError {
            switch processError {
            case .timedOut:
                throw RestrictedConversationResponderError.invocationTimedOut
            case .launchFailed, .nonZeroExit:
                throw RestrictedConversationResponderError.invocationFailed
            }
        } catch is CancellationError {
            // The run was stopped: cancellation propagates unchanged so the
            // service records the honest canceled outcome.
            throw CancellationError()
        } catch {
            throw RestrictedConversationResponderError.invocationFailed
        }

        return try Self.parseResponse(from: result.stdout, request: request, context: context)
    }

    // MARK: Prompt composition

    /// Builds the full stdin payload and enforces the hard UTF-8 byte limit.
    /// Fixed sections come first; the durable follow-up turns fill whatever
    /// remains, newest first, so the oldest turns are always the ones cut or
    /// dropped. Every reduction is declared in the prompt itself.
    static func composePrompt(
        request: ConversationRequest,
        contextDocument: String
    ) throws -> Data {
        let prefix = [
            "You are the local reflection agent inside Reflect, a private macOS app. "
                + "Answer the current question about the user's own recorded reflections.",
            "",
            "Rules:",
            "- Use only the approved context and the conversation turns provided here.",
            "- If they are insufficient, say so plainly instead of guessing or inventing details.",
            "- Never invent context items, references, assessments, or competence claims.",
            "- Answer in English.",
            "",
            "Request:",
            "- requestID: \(request.id)",
            "- conversationID: \(request.conversationID)",
            "",
            "Current question:",
            request.question,
            "",
            "Approved context (bounded; the only evidence you may cite):",
            contextDocument
        ].joined(separator: "\n")

        let turnsHeading = "Conversation so far (this conversation's durable prior exchange, most recent last):"
        let noTurnsLine = "No prior turns."
        let outputContract = """
            Output contract (strict):
            - Reply with exactly one JSON object and nothing else: no prose, no markdown, no code fences.
            - Required shape:
              {"requestID": "<repeat the requestID above exactly>", "answerText": "<your answer in English>", "referencedContextItemIDs": ["<only IDs of context items above that you actually used>"]}
            - Use an empty referencedContextItemIDs array when no context item applies.
            - Never include any other keys or text.
            """

        func assembled(_ includedTurns: [String]) -> String {
            let turnsBlock = includedTurns.isEmpty
                ? noTurnsLine
                : includedTurns.reversed().joined(separator: "\n")
            return [prefix, turnsHeading, turnsBlock, outputContract].joined(separator: "\n\n")
        }

        // The room left for turns is the total minus the fixed prompt with an
        // empty turns block (which reserves the same separators).
        let fixedPrompt = [prefix, turnsHeading, "", outputContract].joined(separator: "\n\n")
        let remainingForTurns = Self.maxStdinBytes - Self.utf8ByteCount(fixedPrompt)
        let requiredRoom = request.followUpTurns.isEmpty ? 0 : Self.minimumTurnAllowance
        guard remainingForTurns >= requiredRoom else {
            throw RestrictedConversationResponderError.promptTooLarge
        }

        var included: [String] = []
        var includedBytes = 0
        var cutOldestIncludedTurn = false

        for turn in request.followUpTurns.reversed() {
            let rendered = Self.renderedTurnText(turn)
            let joinerBytes = included.isEmpty ? 0 : 1
            let renderedBytes = Self.utf8ByteCount(rendered)
            if includedBytes + joinerBytes + renderedBytes <= remainingForTurns {
                included.append(rendered)
                includedBytes += joinerBytes + renderedBytes
                continue
            }

            // The oldest side is reduced first: try cutting this turn to the
            // remaining room before dropping it entirely. The marker's bytes
            // are reserved up front, so a kept cut is always a real cut.
            let availableForBody = remainingForTurns - includedBytes - joinerBytes
                - Self.utf8ByteCount(Self.cutTurnMarker)
            let cutBody = ContextSerializer.truncatingToUTF8ByteLimit(rendered, maxBytes: availableForBody)
            if availableForBody > 0, !cutBody.isEmpty {
                included.append(cutBody + Self.cutTurnMarker)
                cutOldestIncludedTurn = true
            }
            break
        }
        // The cut turn counts as included; everything older is omitted. The
        // per-turn accounting above matches `assembled`'s "\n" join exactly.
        var omittedCount = request.followUpTurns.count - included.count

        if omittedCount > 0 || cutOldestIncludedTurn {
            included.append(Self.reductionMarker(omittedCount: omittedCount, cutOldest: cutOldestIncludedTurn))
            // This recomputation is the exact serialized prompt, including
            // the marker and every join byte around it. If it exceeds the
            // cap, further oldest turns are dropped — each one counted in
            // the rebuilt marker — until it fits. Terminates because the
            // marker alone is far smaller than the reserved turn allowance,
            // so the marker-only prompt always fits.
            while Self.utf8ByteCount(assembled(included)) > Self.maxStdinBytes, included.count > 1 {
                let dropped = included.remove(at: included.count - 2)
                if dropped.hasSuffix(Self.cutTurnMarker) {
                    cutOldestIncludedTurn = false
                }
                omittedCount += 1
                included[included.count - 1] = Self.reductionMarker(
                    omittedCount: omittedCount,
                    cutOldest: cutOldestIncludedTurn
                )
            }
        }

        let prompt = assembled(included)
        guard Self.utf8ByteCount(prompt) <= Self.maxStdinBytes else {
            throw RestrictedConversationResponderError.promptTooLarge
        }
        return Data(prompt.utf8)
    }

    private static func renderedTurnText(_ turn: ConversationFollowUpTurn) -> String {
        let speakerLabel: String
        switch turn.speaker {
        case .user: speakerLabel = "[you]"
        case .assistant: speakerLabel = "[assistant]"
        }
        return speakerLabel + " " + turn.text
    }

    private static func reductionMarker(omittedCount: Int, cutOldest: Bool) -> String {
        var notes: [String] = []
        if omittedCount > 0 {
            notes.append("\(omittedCount) earlier conversation turn(s) were omitted to fit the size limit.")
        }
        if cutOldest {
            notes.append("The oldest included conversation turn was cut to fit the size limit.")
        }
        return "[Note: " + notes.joined(separator: " ") + "]"
    }

    private static func utf8ByteCount(_ text: String) -> Int {
        text.utf8.count
    }

    // MARK: Strict output parsing

    private struct AgentJSONPayload: Decodable {
        let requestID: String
        let answerText: String
        let referencedContextItemIDs: [String]

        enum CodingKeys: String, CodingKey {
            case requestID
            case answerText
            case referencedContextItemIDs
        }
    }

    /// The only top-level keys the strict output contract permits.
    private static let permittedPayloadKeys: Set<String> = [
        AgentJSONPayload.CodingKeys.requestID.stringValue,
        AgentJSONPayload.CodingKeys.answerText.stringValue,
        AgentJSONPayload.CodingKeys.referencedContextItemIDs.stringValue,
    ]

    /// Rejects any top-level key outside the three required fields before
    /// decoding: `JSONDecoder` would silently ignore unknown keys, and a
    /// reply that adds them does not follow the contract. Such a reply is
    /// rejected as a whole, never partially trusted.
    private static func validateTopLevelKeys(in payloadData: Data) throws {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: payloadData)
        } catch {
            throw RestrictedConversationResponderError.invalidOutput
        }
        guard let payloadObject = object as? [String: Any],
              Set(payloadObject.keys) == Self.permittedPayloadKeys else {
            throw RestrictedConversationResponderError.invalidOutput
        }
    }

    /// Parses the agent's stdout as exactly one strict JSON object carrying
    /// exactly the three required top-level fields — unknown keys are
    /// rejected before decoding. Empty, malformed, oversize, or request-
    /// mismatched output is rejected without repair, and the raw output is
    /// never surfaced. Reference grounding is delegated to the existing
    /// `ResponseValidator`; no model or usage is ever fabricated.
    static func parseResponse(
        from stdout: Data,
        request: ConversationRequest,
        context: ContextEnvelope
    ) throws -> ConversationResponse {
        guard stdout.count <= Self.maxOutputBytes else {
            throw RestrictedConversationResponderError.invalidOutput
        }

        let trimmed = String(decoding: stdout, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RestrictedConversationResponderError.invalidOutput
        }

        let payloadData = Data(trimmed.utf8)
        try Self.validateTopLevelKeys(in: payloadData)

        let payload: AgentJSONPayload
        do {
            payload = try JSONDecoder().decode(AgentJSONPayload.self, from: payloadData)
        } catch {
            throw RestrictedConversationResponderError.invalidOutput
        }

        guard payload.requestID == request.id else {
            throw RestrictedConversationResponderError.invalidOutput
        }
        guard !payload.answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RestrictedConversationResponderError.invalidOutput
        }

        let response = ConversationResponse(
            requestID: payload.requestID,
            answerText: payload.answerText,
            referencedContextItemIDs: payload.referencedContextItemIDs,
            modelReportedByProvider: nil,
            usage: nil
        )
        // Reference grounding against the request's actual envelope is the
        // existing validator's job; an unknown reference is a rejection.
        try ResponseValidator.validate(response, expectedRequestID: request.id, envelope: context)
        return response
    }
}
