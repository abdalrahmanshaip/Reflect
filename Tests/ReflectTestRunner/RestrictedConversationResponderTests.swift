import Foundation
@testable import ReflectLib

/// Focused tests for `RestrictedConversationResponder`. Every fixture here is
/// synthetic: the process runner is always a recording fake that launches
/// nothing, no provider is contacted, and the only "secrets" are harmless
/// `ReflectFixture` marker strings.
enum RestrictedConversationResponderTests {
    // MARK: Synthetic fixture builders

    private struct FixtureFailure: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    private static func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw FixtureFailure(message: message) }
    }

    private static func caughtError<T>(_ body: () throws -> T) -> Error? {
        do {
            _ = try body()
            return nil
        } catch {
            return error
        }
    }

    private static func expectResponderError(
        _ caught: Error?,
        _ expected: RestrictedConversationResponderError,
        _ context: String
    ) throws {
        guard let caught else {
            throw FixtureFailure(message: "\(context): expected \(expected) but nothing was thrown.")
        }
        guard let responderError = caught as? RestrictedConversationResponderError, responderError == expected else {
            throw FixtureFailure(message: "\(context): expected \(expected), got \(caught).")
        }
    }

    /// Bounded async-to-sync bridge state. Declared at file/enum scope
    /// because Swift forbids nested types inside a generic function.
    private final class AsyncTestBox<T> {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<T, Error>?
    }

    /// Bridges an async body into the synchronous `TestEntry` harness with a
    /// bounded wait, rethrowing whatever the body threw.
    private static func runAwaiting<T>(_ body: @escaping () async throws -> T) throws -> T {
        let box = AsyncTestBox<T>()
        Task {
            do {
                box.result = Result<T, Error>.success(try await body())
            } catch {
                box.result = Result<T, Error>.failure(error)
            }
            box.semaphore.signal()
        }
        guard box.semaphore.wait(timeout: .now() + 60) == .success else {
            throw FixtureFailure(message: "Asynchronous fixture work did not finish within 60 seconds.")
        }
        switch box.result {
        case .success(let value): return value
        case .failure(let error): throw error
        case nil: throw FixtureFailure(message: "Asynchronous fixture work finished without a result.")
        }
    }

    /// Recording fake: captures the single invocation and returns the
    /// injected synthetic outcome. It never spawns or inspects a process.
    private final class RecordingProcessRunner: AnalysisDiscoveryProcessRunning {
        private let outcome: Result<AnalysisProcessResult, Error>
        private(set) var invocations: [AnalysisProcessInvocation] = []
        private(set) var sawWorkingDirectoryDuringCall = false

        init(returning outcome: Result<AnalysisProcessResult, Error>) {
            self.outcome = outcome
        }

        func run(_ invocation: AnalysisProcessInvocation) async throws -> AnalysisProcessResult {
            invocations.append(invocation)
            sawWorkingDirectoryDuringCall = FileManager.default.fileExists(atPath: invocation.workingDirectory.path)
            return try outcome.get()
        }
    }

    private static func makeSyntheticRequest(
        question: String = "ReflectFixtureQuestion: what did I focus on?",
        followUpTurns: [ConversationFollowUpTurn] = []
    ) -> ConversationRequest {
        ConversationRequest(
            id: UUID().uuidString,
            conversationID: UUID().uuidString,
            question: question,
            requestedAt: Date(timeIntervalSince1970: 1_700_000_000),
            followUpTurns: followUpTurns
        )
    }

    /// A minimal, fully synthetic envelope: no items, no stores, no notes.
    /// It only needs to be a valid instance for the serializer/validator.
    private static func makeSyntheticEnvelope() throws -> ContextEnvelope {
        let budget = try BoundedContextBudget(maxItemCount: 8, maxByteCount: 8192, maxTurnCount: 8)
        let coverage = try BoundedContextCoverage(
            includedItemCount: 0,
            omittedItemCount: 0,
            truncatedItemCount: 0,
            includedByteCount: 0,
            includedTurnCount: 0,
            state: .unknown
        )
        let descriptor = try BoundedContextDescriptor(budget: budget, coverage: coverage)
        return ContextEnvelope(
            generatedAt: Date(timeIntervalSince1970: 0),
            requestTerms: ["reflect-fixture-term"],
            comparisonRequested: false,
            items: [],
            omittedItemIDs: [],
            truncatedItemIDs: [],
            descriptor: descriptor,
            earlierExamples: .notRequested,
            outcome: .noRelevantHistory,
            missingStores: [],
            dateCoverage: ContextDateCoverage(
                earliest: nil,
                latest: nil,
                includesApproximateOrMissingTimes: false
            ),
            sourceKinds: [],
            uncertaintyNotes: []
        )
    }

    private static func makeVerifiedResponder(
        kind: AnalysisAgentKind = .codex,
        model: String? = nil,
        runner: AnalysisDiscoveryProcessRunning
    ) throws -> RestrictedConversationResponder {
        try RestrictedConversationResponder(
            agentKind: kind,
            selectedModelOptionID: model,
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            processRunner: runner
        )
    }

    private static func replyJSON(
        requestID: String,
        answer: String,
        references: [String] = []
    ) -> String {
        let referenceList = references
            .map { "\"\($0)\"" }
            .joined(separator: ",")
        return "{\"requestID\":\"\(requestID)\",\"answerText\":\"\(answer)\",\"referencedContextItemIDs\":[\(referenceList)]}"
    }

    private static func successfulReplyRunner(request: ConversationRequest) -> RecordingProcessRunner {
        let reply = replyJSON(
            requestID: request.id,
            answer: "ReflectFixtureSyntheticAnswer-回答-OK"
        )
        return RecordingProcessRunner(
            returning: .success(
                AnalysisProcessResult(
                    stdout: Data(reply.utf8),
                    stderr: Data(),
                    terminationStatus: 0
                )
            )
        )
    }

    // MARK: Prompt composition

    private static func testComposePromptEmbedsEnvelopeWithinByteCap() throws {
        let contextDocument = "ReflectFixtureApprovedContext-item-alpha / ReflectFixtureApprovedContext-item-beta-β"
        let turns = [
            ConversationFollowUpTurn(speaker: .user, text: "ReflectFixtureOlderUserTurn-older-前"),
            ConversationFollowUpTurn(speaker: .assistant, text: "ReflectFixtureAssistantTurn-mid-middle"),
            ConversationFollowUpTurn(speaker: .user, text: "ReflectFixtureNewestUserTurn-newest-後"),
        ]
        let request = makeSyntheticRequest(followUpTurns: turns)

        let promptData = try RestrictedConversationResponder.composePrompt(
            request: request,
            contextDocument: contextDocument
        )

        try check(promptData.count <= 65_536, "Prompt exceeded the 64 KiB UTF-8 cap: \(promptData.count) bytes.")
        let prompt = String(decoding: promptData, as: UTF8.self)
        try check(prompt.contains(request.id), "Prompt is missing the request ID.")
        try check(prompt.contains(request.conversationID), "Prompt is missing the conversation ID.")
        try check(prompt.contains(request.question), "Prompt is missing the current question.")
        try check(prompt.contains(contextDocument), "Prompt is missing the approved context document.")
        try check(prompt.contains("ReflectFixtureOlderUserTurn"), "Prompt is missing the oldest follow-up turn.")
        try check(prompt.contains("ReflectFixtureAssistantTurn"), "Prompt is missing the assistant follow-up turn.")
        try check(prompt.contains("ReflectFixtureNewestUserTurn"), "Prompt is missing the newest follow-up turn.")
        let olderLocation = try checkLocation(of: "ReflectFixtureOlderUserTurn", in: prompt)
        let newestLocation = try checkLocation(of: "ReflectFixtureNewestUserTurn", in: prompt)
        try check(olderLocation < newestLocation, "Follow-up turns are not rendered most recent last.")
        try check(prompt.contains("[you]"), "User turns are missing their speaker label.")
        try check(prompt.contains("[assistant]"), "Assistant turns are missing their speaker label.")
        try check(!prompt.contains("omitted"), "Prompt declares reductions even though every turn fit.")

        let noTurnsData = try RestrictedConversationResponder.composePrompt(
            request: makeSyntheticRequest(),
            contextDocument: contextDocument
        )
        try check(noTurnsData.count <= 65_536, "No-turn prompt exceeded the 64 KiB UTF-8 cap.")
        let noTurnsPrompt = String(decoding: noTurnsData, as: UTF8.self)
        try check(noTurnsPrompt.contains("No prior turns."), "No-turn prompt does not declare the empty history.")
    }

    private static func checkLocation(of needle: String, in prompt: String) throws -> String.Index {
        guard let location = prompt.range(of: needle)?.lowerBound else {
            throw FixtureFailure(message: "Expected marker \(needle) is missing from the prompt.")
        }
        return location
    }

    /// Long multibyte follow-up turns overflow the cap: the newest turn must
    /// survive and every older reduction must be declared with a count.
    private static func testComposePromptLongMultibyteHistoryDeclaresReductions() throws {
        let hugeOldTurn = ConversationFollowUpTurn(
            speaker: .user,
            text: "ReflectFixtureOldestMarker-隠された-"
                + String(repeating: "回", count: 50_000)
                + "-ReflectFixtureOldestTailMarker"
        )
        let hugeMiddleTurn = ConversationFollowUpTurn(
            speaker: .assistant,
            text: "ReflectFixtureMiddleMarker-中間-"
                + String(repeating: "字", count: 50_000)
                + "-ReflectFixtureMiddleTailMarker"
        )
        let newestTurn = ConversationFollowUpTurn(
            speaker: .user,
            text: "ReflectFixtureNewestMarker-最新-😀 kept in full"
        )
        let request = makeSyntheticRequest(followUpTurns: [hugeOldTurn, hugeMiddleTurn, newestTurn])

        let promptData = try RestrictedConversationResponder.composePrompt(
            request: request,
            contextDocument: "ReflectFixtureApprovedContext-small"
        )

        try check(promptData.count <= 65_536, "Reduced prompt exceeded the 64 KiB UTF-8 cap: \(promptData.count) bytes.")
        let prompt = String(decoding: promptData, as: UTF8.self)
        try check(prompt.contains("ReflectFixtureNewestMarker"), "The newest turn was dropped; reductions must cut the oldest side first.")
        try check(!prompt.contains("ReflectFixtureOldestMarker"), "An omitted oldest turn leaked into the prompt.")
        try check(!prompt.contains("ReflectFixtureOldestTailMarker"), "An omitted oldest turn leaked into the prompt.")
        try check(!prompt.contains("ReflectFixtureMiddleMarker"), "An omitted middle turn leaked into the prompt.")
        try check(!prompt.contains("ReflectFixtureMiddleTailMarker"), "An omitted middle turn leaked into the prompt.")
        try check(
            prompt.contains("were omitted to fit the size limit"),
            "The prompt does not declare that older turns were omitted."
        )
        try check(
            prompt.contains("2 earlier conversation turn(s) were omitted"),
            "The omission note does not carry the declared count of omitted turns."
        )
    }

    private static func testComposePromptThrowsWhenFixedPartsAloneExceedCap() throws {
        let oversizedContext = String(repeating: "A", count: 70_000)

        let noTurnsError = caughtError {
            try RestrictedConversationResponder.composePrompt(
                request: makeSyntheticRequest(),
                contextDocument: oversizedContext
            )
        }
        try expectResponderError(noTurnsError, .promptTooLarge, "Oversized fixed parts without turns")

        let withTurnsError = caughtError {
            try RestrictedConversationResponder.composePrompt(
                request: makeSyntheticRequest(followUpTurns: [
                    ConversationFollowUpTurn(speaker: .user, text: "ReflectFixtureSmallTurn"),
                ]),
                contextDocument: oversizedContext
            )
        }
        try expectResponderError(withTurnsError, .promptTooLarge, "Oversized fixed parts with turns")
    }

    // MARK: Strict output parsing

    private static func testParseResponseAcceptsStrictThreeKeyReply() throws {
        let request = makeSyntheticRequest()
        let envelope = try makeSyntheticEnvelope()
        let reply = replyJSON(
            requestID: request.id,
            answer: "ReflectFixtureParsedAnswer-解析-OK",
            references: []
        )

        let response = try RestrictedConversationResponder.parseResponse(
            from: Data(reply.utf8),
            request: request,
            context: envelope
        )

        try check(response.requestID == request.id, "Parsed response carries the wrong request ID.")
        try check(response.answerText == "ReflectFixtureParsedAnswer-解析-OK", "Parsed response carries the wrong answer text.")
        try check(response.referencedContextItemIDs.isEmpty, "Parsed response invented context references.")
        try check(response.modelReportedByProvider == nil, "Model identifier must stay nil for this transport.")
        try check(response.usage == nil, "Usage must stay nil for this transport.")
    }

    private static func testParseResponseRejectsUnusableReplies() throws {
        let request = makeSyntheticRequest()
        let envelope = try makeSyntheticEnvelope()

        let malformedCases: [String: Data] = [
            "empty output": Data(),
            "whitespace-only output": Data("   \n ".utf8),
            "malformed JSON": Data("not json at all".utf8),
            "truncated JSON": Data("{\"requestID\":\"\(request.id)\",\"answerText\":\"ReflectFixtureCut\"".utf8),
            "array top level": Data("[]".utf8),
            "missing referencedContextItemIDs": Data(
                "{\"requestID\":\"\(request.id)\",\"answerText\":\"ReflectFixtureAnswer\"}".utf8
            ),
            "mismatched request ID": Data(
                replyJSON(requestID: UUID().uuidString, answer: "ReflectFixtureAnswer").utf8
            ),
            "blank answer text": Data(
                replyJSON(requestID: request.id, answer: "   ").utf8
            ),
            "oversize output": Data(repeating: UInt8(ascii: " "), count: 64 * 1024 + 1),
        ]

        // The extra-key case is a valid object apart from the fourth key,
        // which the strict contract rejects before decoding.
        let extraKeyJSON = "{\"requestID\":\"\(request.id)\",\"answerText\":\"ReflectFixtureAnswer\","
            + "\"referencedContextItemIDs\":[],\"model\":\"reflect-fabricated-model\"}"
        var cases = malformedCases
        cases["extra top-level key"] = Data(extraKeyJSON.utf8)

        for (label, output) in cases.sorted(by: { $0.key < $1.key }) {
            let caught = caughtError {
                try RestrictedConversationResponder.parseResponse(
                    from: output,
                    request: request,
                    context: envelope
                )
            }
            try expectResponderError(caught, .invalidOutput, "parseResponse rejection (\(label))")
        }
    }

    private static func testParseResponseRejectsUnknownContextReference() throws {
        let request = makeSyntheticRequest()
        let envelope = try makeSyntheticEnvelope()
        let reply = replyJSON(
            requestID: request.id,
            answer: "ReflectFixtureAnswer",
            references: ["reflect-fixture-unknown-item-id"]
        )

        let caught = caughtError {
            try RestrictedConversationResponder.parseResponse(
                from: Data(reply.utf8),
                request: request,
                context: envelope
            )
        }
        guard caught != nil else {
            throw FixtureFailure(message: "An unknown context reference was accepted instead of rejected.")
        }
    }

    // MARK: Restricted invocation through the fake runner

    private static func testRespondUsesRestrictedInvocationAndIsolatedTemporaryDirectory() throws {
        let request = makeSyntheticRequest()
        let envelope = try makeSyntheticEnvelope()
        let runner = successfulReplyRunner(request: request)
        let responder = try makeVerifiedResponder(runner: runner)

        let response = try runAwaiting { try await responder.respond(to: request, context: envelope) }

        try check(response.requestID == request.id, "Response is not tied to the request ID echoed by the fake JSON.")
        try check(response.answerText == "ReflectFixtureSyntheticAnswer-回答-OK", "Response does not match the fake reply text.")
        try check(response.modelReportedByProvider == nil, "Model identifier must stay nil for this transport.")
        try check(response.usage == nil, "Usage must stay nil for this transport.")

        // Run a second request through a fresh fake to confirm per-call
        // isolation and uniqueness of the temporary working directory.
        let secondRequest = makeSyntheticRequest()
        let secondRunner = successfulReplyRunner(request: secondRequest)
        let secondResponder = try makeVerifiedResponder(runner: secondRunner)
        _ = try runAwaiting { try await secondResponder.respond(to: secondRequest, context: envelope) }

        let recorded = runner.invocations
        let secondRecorded = secondRunner.invocations
        try check(recorded.count == 1, "The responder invoked the process runner more than once per request: \(recorded.count).")
        try check(secondRecorded.count == 1, "The responder invoked the process runner more than once per request: \(secondRecorded.count).")

        let invocation = recorded[0]
        let secondInvocation = secondRecorded[0]

        try check(
            invocation.executableURL == URL(fileURLWithPath: "/bin/sh"),
            "The invocation did not target the explicitly verified executable."
        )
        let expectedArguments = AnalysisAgentKind.codex.analysisArguments(model: nil)
        try check(
            invocation.arguments == expectedArguments,
            "The invocation arguments are not exactly the agent kind's restricted arguments: \(invocation.arguments)"
        )
        try check(invocation.input.count <= 65_536, "Stdin payload exceeded the 64 KiB cap: \(invocation.input.count) bytes.")
        let prompt = String(decoding: invocation.input, as: UTF8.self)
        try check(prompt.contains(request.question), "Stdin payload is missing the current question.")

        let allowlistedEnvironmentKeys: Set<String> = [
            "PATH", "HOME", "CODEX_HOME", "CLAUDE_CONFIG_DIR", "COPILOT_HOME", "LANG", "LC_ALL",
        ]
        try check(
            invocation.environment.keys.allSatisfy { allowlistedEnvironmentKeys.contains($0) },
            "The invocation environment carried non-allowlisted keys: \(invocation.environment.keys.sorted())"
        )

        try check(
            invocation.workingDirectory.lastPathComponent.hasPrefix("ReflectConversation-"),
            "The working directory is not the responder's isolated ReflectConversation- prefix: \(invocation.workingDirectory.path)"
        )
        try check(
            invocation.workingDirectory != secondInvocation.workingDirectory,
            "Two calls reused the same working directory."
        )
        try check(
            runner.sawWorkingDirectoryDuringCall,
            "The isolated working directory did not exist while the fake runner observed the invocation."
        )
        try check(
            secondRunner.sawWorkingDirectoryDuringCall,
            "The second isolated working directory did not exist while the fake runner observed the invocation."
        )
        try check(invocation.timeout == 120, "The invocation timeout is not the documented 120 second limit.")
        try check(invocation.outputLimit == 64 * 1024 + 1, "The retained output limit is not the documented 64 KiB + 1 sentinel.")

        try check(
            FileManager.default.fileExists(atPath: invocation.workingDirectory.path) == false,
            "The isolated working directory still exists after respond returned."
        )
        try check(
            FileManager.default.fileExists(atPath: secondInvocation.workingDirectory.path) == false,
            "The second isolated working directory still exists after respond returned."
        )
    }

    private static func testRespondMapsFakeProcessFailures() throws {
        let request = makeSyntheticRequest()
        let envelope = try makeSyntheticEnvelope()

        let timedOutRunner = RecordingProcessRunner(returning: .failure(AnalysisProcessError.timedOut))
        let timedOutResponder = try makeVerifiedResponder(runner: timedOutRunner)
        let timedOutError = caughtError {
            try runAwaiting { try await timedOutResponder.respond(to: request, context: envelope) }
        }
        try expectResponderError(timedOutError, .invocationTimedOut, "Fake timeout mapping")

        let launchFailedRunner = RecordingProcessRunner(returning: .failure(AnalysisProcessError.launchFailed))
        let launchFailedResponder = try makeVerifiedResponder(runner: launchFailedRunner)
        let launchFailedError = caughtError {
            try runAwaiting { try await launchFailedResponder.respond(to: request, context: envelope) }
        }
        try expectResponderError(launchFailedError, .invocationFailed, "Fake launch failure mapping")

        let nonZeroRunner = RecordingProcessRunner(returning: .failure(AnalysisProcessError.nonZeroExit(3)))
        let nonZeroResponder = try makeVerifiedResponder(runner: nonZeroRunner)
        let nonZeroError = caughtError {
            try runAwaiting { try await nonZeroResponder.respond(to: request, context: envelope) }
        }
        try expectResponderError(nonZeroError, .invocationFailed, "Fake nonzero exit mapping")

        let canceledRunner = RecordingProcessRunner(returning: .failure(CancellationError()))
        let canceledResponder = try makeVerifiedResponder(runner: canceledRunner)
        let canceledError = caughtError {
            try runAwaiting { try await canceledResponder.respond(to: request, context: envelope) }
        }
        guard let canceledError, canceledError is CancellationError else {
            throw FixtureFailure(message: "Fake cancellation: expected CancellationError, got \(String(describing: canceledError)).")
        }
    }

    private static func testResponderInitRefusals() throws {
        let unsupportedAgentError = caughtError {
            try makeVerifiedResponder(kind: .copilotCLI, runner: successfulReplyRunner(request: makeSyntheticRequest()))
        }
        try expectResponderError(unsupportedAgentError, .unsupportedAgentKind, "Unsupported agent kind refusal")

        let unsupportedModelError = caughtError {
            try makeVerifiedResponder(
                kind: .codex,
                model: "reflect-fixture-unknown-model",
                runner: successfulReplyRunner(request: makeSyntheticRequest())
            )
        }
        try expectResponderError(unsupportedModelError, .unsupportedModelOption, "Unsupported model option refusal")

        let nonexistentURLError = caughtError {
            try RestrictedConversationResponder(
                agentKind: .codex,
                selectedModelOptionID: nil,
                executableURL: URL(fileURLWithPath: "/nonexistent-reflect-fixture-\(UUID().uuidString)"),
                processRunner: RecordingProcessRunner(returning: .success(
                    AnalysisProcessResult(stdout: Data(), stderr: Data(), terminationStatus: 0)
                ))
            )
        }
        try expectResponderError(nonexistentURLError, .agentNotVerified, "Nonexistent executable refusal")

        let nonFileURLError = caughtError {
            try RestrictedConversationResponder(
                agentKind: .codex,
                selectedModelOptionID: nil,
                executableURL: URL(string: "https://reflect.fixture.invalid/agent")!,
                processRunner: RecordingProcessRunner(returning: .success(
                    AnalysisProcessResult(stdout: Data(), stderr: Data(), terminationStatus: 0)
                ))
            )
        }
        try expectResponderError(nonFileURLError, .agentNotVerified, "Non-file URL refusal")
    }

    // MARK: Registry

    static let entries: [TestEntry] = [
        TestEntry(
            suite: "RestrictedConversationResponderTests",
            name: "composePrompt embeds request identity, question, approved context, and turns within the byte cap"
        ) {
            try testComposePromptEmbedsEnvelopeWithinByteCap()
        },
        TestEntry(
            suite: "RestrictedConversationResponderTests",
            name: "composePrompt keeps the newest multibyte turn and declares omitted older turns with a count"
        ) {
            try testComposePromptLongMultibyteHistoryDeclaresReductions()
        },
        TestEntry(
            suite: "RestrictedConversationResponderTests",
            name: "composePrompt throws promptTooLarge when the fixed parts alone exceed the cap"
        ) {
            try testComposePromptThrowsWhenFixedPartsAloneExceedCap()
        },
        TestEntry(
            suite: "RestrictedConversationResponderTests",
            name: "parseResponse accepts a strict three-key reply and fabricates no model or usage"
        ) {
            try testParseResponseAcceptsStrictThreeKeyReply()
        },
        TestEntry(
            suite: "RestrictedConversationResponderTests",
            name: "parseResponse rejects empty, malformed, incomplete, extra-key, mismatched, blank, oversize, and unknown-reference replies"
        ) {
            try testParseResponseRejectsUnusableReplies()
            try testParseResponseRejectsUnknownContextReference()
        },
        TestEntry(
            suite: "RestrictedConversationResponderTests",
            name: "respond runs the verified executable once with restricted arguments, sanitized environment, unique isolated temp directory, and the fake reply"
        ) {
            try testRespondUsesRestrictedInvocationAndIsolatedTemporaryDirectory()
        },
        TestEntry(
            suite: "RestrictedConversationResponderTests",
            name: "respond maps fake timeout, launch failure, nonzero exit, and cancellation to safe outcomes"
        ) {
            try testRespondMapsFakeProcessFailures()
        },
        TestEntry(
            suite: "RestrictedConversationResponderTests",
            name: "init refuses unsupported agents and models and unverified executable URLs"
        ) {
            try testResponderInitRefusals()
        },
    ]
}
