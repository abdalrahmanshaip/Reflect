import Foundation

struct AnalysisResult {
    let text: String
    let inputTokens: Int?
    let outputTokens: Int?
    let estimatedCostUSD: Double?
    let model: String
    let endpoint: String
    let usedRequestedUsage: Bool
    let agent: AnalysisAgentKind
}

/// Runs only the selected evidence through a verified, authenticated local CLI.
/// The CLI receives the evidence over stdin and never receives a path to the
/// user's evidence store or repository.
struct AnalysisService {
    enum Status: Equatable {
        case disabled
        case incomplete(reason: String)
        case ready
    }

    static func status(settings: AppSettings, agentAvailable: Bool) -> Status {
        guard settings.aiEnabled else { return .disabled }
        guard settings.analysisAgent != nil else {
            return .incomplete(reason: "Choose an authenticated analysis agent.")
        }
        guard agentAvailable else {
            return .incomplete(reason: "The selected agent is not currently authenticated.")
        }
        return .ready
    }

    static let defaultInstruction = """
    You are a cautious engineering-growth coach. Work only from the evidence lines provided. \
    Do not use tools, inspect files, inspect the working directory, or access any external service. \
    Distinguish clearly between observed facts and your interpretations. Do not assert human \
    authorship from metadata. If evidence is insufficient for a conclusion, say so instead of \
    producing a score or ranking.
    """

    static func buildInput(
        events: [EvidenceEvent],
        maxPreviewCharacters: Int,
        instruction: String = AnalysisService.defaultInstruction,
        corrections: [AttributionCorrection] = []
    ) -> Data {
        let selectedIDs = Set(events.map(\.id))
        // Only corrections for selected records are ever serialized; the
        // observed labels below stay exactly as recorded at import time.
        let applicableCorrections = corrections.filter { selectedIDs.contains($0.eventId) }
        var lines = [instruction, "", "Selected evidence records (one per line):"]
        for event in events {
            let time = ISO8601DateFormatter().string(from: event.timestamp)
            var line = "- id=\(event.id) | source=\(event.sourceName) | time=\(time) | type=\(event.kind.label) | observed=\(event.observedAttribution.label)"
            if !event.detail.isEmpty {
                line += " | preview=\(JSONParsing.cappedPreview(event.detail, limit: maxPreviewCharacters))"
            }
            lines.append(line)
        }
        if !applicableCorrections.isEmpty {
            lines.append("")
            lines.append("User attribution corrections (explicit user decisions, kept separate from the observed records above; the observed labels are unchanged):")
            for correction in applicableCorrections {
                guard let event = events.first(where: { $0.id == correction.eventId }) else { continue }
                lines.append("- id=\(event.id) | your correction=\(correction.attribution.label) (user replaces the observed label \(event.observedAttribution.label) for this analysis)")
            }
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    func run(
        selectedEvents: [EvidenceEvent],
        settings: AppSettings,
        agent: AnalysisAgentStatus,
        corrections: [AttributionCorrection] = [],
        processRunner: AnalysisProcessRunning = DefaultAnalysisProcessRunner(),
        temporaryDirectory: URL? = nil
    ) throws -> AnalysisResult {
        guard !selectedEvents.isEmpty else { throw AnalysisError.noEvidenceSelected }
        guard settings.aiEnabled else { throw AnalysisError.disabled }
        guard agent.isReady, let executableURL = agent.executableURL else {
            throw AnalysisError.agentUnavailable
        }

        let workingDirectory: URL
        let ownsWorkingDirectory: Bool
        if let temporaryDirectory {
            workingDirectory = temporaryDirectory
            ownsWorkingDirectory = false
        } else {
            workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("Reflect-analysis-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            ownsWorkingDirectory = true
        }
        defer {
            if ownsWorkingDirectory {
                try? FileManager.default.removeItem(at: workingDirectory)
            }
        }

        let model = settings.model(for: agent.kind)
        let invocation = AnalysisProcessInvocation(
            executableURL: executableURL,
            arguments: agent.kind.analysisArguments(model: model),
            input: Self.buildInput(
                events: selectedEvents,
                maxPreviewCharacters: settings.maxPreviewCharacters,
                corrections: corrections
            ),
            workingDirectory: workingDirectory,
            environment: AnalysisProcessEnvironment.sanitized(),
            timeout: 120,
            outputLimit: 64 * 1024
        )
        let result = try processRunner.run(invocation)
        let text = String(decoding: result.stdout, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AnalysisError.emptyOutput }

        return AnalysisResult(
            text: text,
            inputTokens: nil,
            outputTokens: nil,
            estimatedCostUSD: nil,
            model: model?.isEmpty == false ? model! : "Agent default",
            endpoint: "",
            usedRequestedUsage: false,
            agent: agent.kind
        )
    }

    enum AnalysisError: LocalizedError {
        case disabled
        case agentUnavailable
        case noEvidenceSelected
        case emptyOutput

        var errorDescription: String? {
            switch self {
            case .disabled: return "AI analysis is disabled."
            case .agentUnavailable: return "The selected analysis agent is not ready."
            case .noEvidenceSelected: return "Select at least one evidence record to send."
            case .emptyOutput: return "The selected analysis agent returned no result."
            }
        }
    }
}
