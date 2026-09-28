import Foundation
@testable import ReflectLib

struct AnalysisServiceTests {
    static let suiteName = "AnalysisServiceTests"

    private func isIncomplete(_ status: AnalysisService.Status) -> Bool {
        if case .incomplete = status { return true }
        return false
    }

    func statusIsDisabledByDefault() throws {
        try expectEqual(AnalysisService.status(settings: AppSettings(), hasKey: true), .disabled)
        try expectEqual(AnalysisService.status(settings: AppSettings(), hasKey: false), .disabled)
    }

    func statusIsIncompleteWithoutEndpointModelOrKey() throws {
        var settings = AppSettings()
        settings.aiEnabled = true

        try expectTrue(isIncomplete(AnalysisService.status(settings: settings, hasKey: false)), "nothing configured should be incomplete")

        settings.providerEndpoint = "https://api.example.com"
        try expectTrue(isIncomplete(AnalysisService.status(settings: settings, hasKey: false)), "expected .incomplete without a model")

        settings.providerModel = "fixture-model"
        try expectTrue(isIncomplete(AnalysisService.status(settings: settings, hasKey: false)), "expected .incomplete without a stored key")
        try expectEqual(AnalysisService.status(settings: settings, hasKey: true), .ready)
    }

    func completionsURLNormalization() throws {
        try expectEqual(
            AnalysisService.completionsURL(from: "https://api.example.com")?.absoluteString,
            "https://api.example.com/v1/chat/completions"
        )
        try expectEqual(
            AnalysisService.completionsURL(from: "https://api.example.com/v1/")?.absoluteString,
            "https://api.example.com/v1/chat/completions"
        )
        try expectEqual(
            AnalysisService.completionsURL(from: "https://api.example.com/v1/chat/completions")?.absoluteString,
            "https://api.example.com/v1/chat/completions"
        )
        try expectNil(AnalysisService.completionsURL(from: "not a url"))
    }

    func buildPayloadSendsOnlySelectedEvents() throws {
        let events = Fixtures.dayEvents(count: 2)
        let payload = AnalysisService.buildPayload(
            model: "fixture-model",
            events: events,
            instruction: "Be cautious.",
            maxPreviewCharacters: 120
        )

        try expectEqual(payload["model"] as? String, "fixture-model")
        try expectEqual(payload["stream"] as? Bool, false)

        let messages = try require(payload["messages"] as? [[String: Any]], "messages array expected")
        try expectEqual(messages.count, 2)
        try expectEqual(messages[0]["role"] as? String, "system")

        let userContent = try require(messages[1]["content"] as? String, "user content expected")
        try expectTrue(userContent.contains(events[0].id))
        try expectTrue(userContent.contains(events[1].id))
        try expectTrue(userContent.contains(events[0].sourceName))
        try expectFalse(userContent.contains("fixture-event-9"), "unselected events must not be sent")
    }

    func estimateTokensIsRoughAndDeterministic() throws {
        try expectEqual(AnalysisService.estimateTokens(String(repeating: "a", count: 400)), 100)
        try expectEqual(AnalysisService.estimateTokens(""), 0)
    }

    static var entries: [TestEntry] {
        let tests = AnalysisServiceTests()
        return [
            TestEntry(suite: suiteName, name: "statusIsDisabledByDefault") { try tests.statusIsDisabledByDefault() },
            TestEntry(suite: suiteName, name: "statusIsIncompleteWithoutEndpointModelOrKey") { try tests.statusIsIncompleteWithoutEndpointModelOrKey() },
            TestEntry(suite: suiteName, name: "completionsURLNormalization") { try tests.completionsURLNormalization() },
            TestEntry(suite: suiteName, name: "buildPayloadSendsOnlySelectedEvents") { try tests.buildPayloadSendsOnlySelectedEvents() },
            TestEntry(suite: suiteName, name: "estimateTokensIsRoughAndDeterministic") { try tests.estimateTokensIsRoughAndDeterministic() }
        ]
    }
}
