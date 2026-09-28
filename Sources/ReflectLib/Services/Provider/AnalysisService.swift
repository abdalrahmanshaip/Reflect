import Foundation

struct AnalysisResult {
    let text: String
    let inputTokens: Int?
    let outputTokens: Int?
    let estimatedCostUSD: Double?
    let model: String
    let endpoint: String
    let usedRequestedUsage: Bool
}

/// Sends an explicit, user-triggered analysis request to an OpenAI-compatible
/// chat-completions endpoint. Only the events the user selected are serialized.
/// This is the only code path in the app that can touch the network.
struct AnalysisService {
    enum Status: Equatable {
        case disabled
        case incomplete(reason: String)
        case ready
    }

    // MARK: Status

    static func status(settings: AppSettings, hasKey: Bool) -> Status {
        guard settings.aiEnabled else { return .disabled }
        if settings.providerEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .incomplete(reason: "Endpoint is missing.")
        }
        if settings.providerModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .incomplete(reason: "Model is missing.")
        }
        if !hasKey {
            return .incomplete(reason: "API key is not stored in Keychain.")
        }
        return .ready
    }

    // MARK: URL handling

    static func completionsURL(from endpoint: String) -> URL? {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host() != nil else { return nil }

        var path = url.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix("/chat/completions") {
            // Already the full path.
        } else if path.hasSuffix("/v1") {
            path += "/chat/completions"
        } else {
            path += "/v1/chat/completions"
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = url.host()
        components.port = url.port
        components.path = path
        return components.url
    }

    // MARK: Payload

    static func buildPayload(
        model: String,
        events: [EvidenceEvent],
        instruction: String,
        maxPreviewCharacters: Int
    ) -> [String: Any] {
        let systemMessage: String
        if instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            systemMessage = defaultInstruction
        } else {
            systemMessage = instruction
        }

        var lines = ["Evidence records selected by the user (one per line):"]
        for event in events {
            let time = ISO8601DateFormatter().string(from: event.timestamp)
            var line = "- id=\(event.id) | source=\(event.sourceName) | time=\(time) | type=\(event.kind.label) | observed=\(event.observedAttribution.label)"
            if !event.detail.isEmpty {
                line += " | preview=\(JSONParsing.cappedPreview(event.detail, limit: maxPreviewCharacters))"
            }
            lines.append(line)
        }

        return [
            "model": model,
            "stream": false,
            "messages": [
                ["role": "system", "content": systemMessage],
                ["role": "user", "content": lines.joined(separator: "\n")]
            ]
        ]
    }

    static let defaultInstruction = """
    You are a cautious engineering-growth coach. Work only from the evidence lines provided. \
    Distinguish clearly between observed facts and your interpretations. Do not assert human \
    authorship from metadata. If evidence is insufficient for a conclusion, say so instead of \
    producing a score or ranking.
    """

    // MARK: Usage estimation

    static func estimateTokens(_ text: String) -> Int {
        text.count / 4
    }

    // MARK: Request

    func run(
        selectedEvents: [EvidenceEvent],
        settings: AppSettings,
        apiKey: String,
        session: URLSession = .shared,
        now: Date = Date()
    ) async throws -> AnalysisResult {
        guard let url = Self.completionsURL(from: settings.providerEndpoint) else {
            throw AnalysisError.invalidEndpoint
        }
        guard !apiKey.isEmpty else { throw AnalysisError.missingKey }
        guard !selectedEvents.isEmpty else { throw AnalysisError.noEvidenceSelected }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload = Self.buildPayload(
            model: settings.providerModel,
            events: selectedEvents,
            instruction: Self.defaultInstruction,
            maxPreviewCharacters: settings.maxPreviewCharacters
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AnalysisError.badResponse }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AnalysisError.httpStatus(http.statusCode, JSONParsing.cappedPreview(body, limit: 300))
        }

        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw AnalysisError.unexpectedResponseFormat
        }

        let usage = json["usage"] as? [String: Any]
        let requestedInput = usage?["prompt_tokens"] as? Int
        let requestedOutput = usage?["completion_tokens"] as? Int

        let inputTokens: Int
        let outputTokens: Int
        var usedRequested = false
        switch settings.usageMode {
        case .requested where requestedInput != nil && requestedOutput != nil:
            inputTokens = requestedInput ?? 0
            outputTokens = requestedOutput ?? 0
            usedRequested = true
        default:
            let serialized = (try? JSONSerialization.data(withJSONObject: payload, options: []))
                .flatMap { String(data: $0, encoding: .utf8) } ?? ""
            inputTokens = Self.estimateTokens(serialized)
            outputTokens = Self.estimateTokens(text)
        }

        var cost: Double?
        if settings.pricePerMillionInput > 0 || settings.pricePerMillionOutput > 0 {
            cost = Double(inputTokens) / 1_000_000 * settings.pricePerMillionInput
                + Double(outputTokens) / 1_000_000 * settings.pricePerMillionOutput
        }

        return AnalysisResult(
            text: text,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            estimatedCostUSD: cost,
            model: settings.providerModel,
            endpoint: url.absoluteString,
            usedRequestedUsage: usedRequested
        )
    }

    enum AnalysisError: LocalizedError {
        case invalidEndpoint
        case missingKey
        case noEvidenceSelected
        case badResponse
        case httpStatus(Int, String)
        case unexpectedResponseFormat

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint: return "The endpoint URL is not valid."
            case .missingKey: return "No API key is stored in Keychain."
            case .noEvidenceSelected: return "Select at least one evidence record to send."
            case .badResponse: return "The server response was not HTTP."
            case .httpStatus(let code, let body): return "Server returned HTTP \(code): \(body)"
            case .unexpectedResponseFormat: return "The response format was not recognized."
            }
        }
    }
}
