import Foundation

/// Normalizes one Codex CLI rollout JSONL file into an ordered session with
/// retained turns, independent of the compact EvidenceEvent adapter
/// (`CodexImporter`), which stays unchanged.
///
/// Boundaries:
/// - Reads only the bytes it is given; the source file is never written.
/// - Parsing is tolerant and verified only against synthetic fixtures:
///   unknown record types are skipped and counted, malformed lines are
///   counted, and empty lines are ignored.
/// - Message text is retained in full up to the retention limit and labeled
///   when capping occurred; the short display preview is capped separately.
/// - Times come only from the source records. Missing times stay absent
///   (marked approximate); they are never fabricated from the file or clock.
/// - "user"-role turns stay explicitly ambiguous: such records can carry
///   tool-injected context, so no human authorship is asserted.
/// - Only source-established titles/projects are kept; file paths stay
///   private bookkeeping and never become project or task names.
struct CodexSessionImporter {
    struct Limits {
        /// Per-turn retention cap for selected text; capping is labeled.
        let retainedTextCharacterLimit: Int
        /// Separate, shorter display preview cap.
        let previewCharacterLimit: Int

        static let standard = Limits(retainedTextCharacterLimit: 20_000, previewCharacterLimit: 160)
    }

    static let parserVersion = "codex-sessions/1"
    static let uncertaintyMalformedLines = "Malformed source lines were skipped."
    static let uncertaintySkippedRecords = "Source records of unsupported or non-conversational types were skipped, so the retained session may be incomplete."

    /// Per-import scan facts, reported to the caller only. They are not
    /// cumulative across imports and are never persisted as fake counts.
    struct ScanReport: Equatable {
        let recordLineCount: Int
        let malformedLineCount: Int
        let skippedRecordCount: Int
    }

    /// The normalized result for one file; the import service turns this
    /// into a persisted `WorkSession`.
    struct NormalizedSession {
        let stableID: String
        let sourceSessionID: String?
        let title: String?
        let project: String?
        let startedAt: Date?
        let startedAtApproximate: Bool
        let turns: [ConversationTurn]
        let missingSessionIdentity: Bool
        let coverage: CoverageSummary
    }

    struct NormalizationOutcome {
        let session: NormalizedSession?
        let scan: ScanReport
    }

    let limits: Limits

    init(limits: Limits = .standard) {
        self.limits = limits
    }

    func matches(fileName: String) -> Bool {
        fileName.hasPrefix("rollout-") && fileName.hasSuffix(".jsonl")
    }

    /// Normalizes the given bytes from `filePath`. Two passes: session
    /// metadata is resolved first so turn identities never depend on record
    /// order inside the file.
    func normalize(data: Data, filePath: String, now: Date = Date()) -> NormalizationOutcome {
        guard let contents = String(data: data, encoding: .utf8) else {
            return NormalizationOutcome(session: nil, scan: ScanReport(recordLineCount: 0, malformedLineCount: 0, skippedRecordCount: 0))
        }

        var recordLineCount = 0
        var malformedLineCount = 0
        var skippedRecordCount = 0
        var sourceSessionID: String?
        var title: String?
        var project: String?
        var sessionStartedAt: Date?
        var parsedLines: [(line: Int, payload: [String: Any], timestamp: Date?)] = []

        for (index, rawLine) in contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            recordLineCount += 1
            guard let object = JSONParsing.object(line) else {
                malformedLineCount += 1
                continue
            }
            let type = object["type"] as? String ?? ""
            let timestamp = TimestampParser.parse(object["timestamp"])
            switch type {
            case "session_meta":
                let payload = object["payload"] as? [String: Any]
                sourceSessionID = SessionIdentity.normalizedID(payload?["id"] as? String)
                title = Self.sourceEstablishedText(payload?["title"])
                project = Self.sourceEstablishedText(payload?["project"])
                if sessionStartedAt == nil { sessionStartedAt = timestamp }
            case "response_item":
                guard let payload = object["payload"] as? [String: Any] else {
                    malformedLineCount += 1
                    continue
                }
                parsedLines.append((index + 1, payload, timestamp))
            default:
                // Known non-conversational records (for example event_msg) and
                // unknown future types are both skipped, never guessed.
                skippedRecordCount += 1
            }
        }

        let stableID = SessionIdentity.sessionID(source: .codex, sourceSessionID: sourceSessionID, filePath: filePath)

        guard sourceSessionID != nil || !parsedLines.isEmpty else {
            return NormalizationOutcome(
                session: nil,
                scan: ScanReport(recordLineCount: recordLineCount, malformedLineCount: malformedLineCount, skippedRecordCount: skippedRecordCount)
            )
        }

        var turns: [ConversationTurn] = []
        turns.reserveCapacity(parsedLines.count)
        for parsed in parsedLines {
            if let turn = self.turn(
                fromPayload: parsed.payload,
                filePath: filePath,
                sourceSessionID: sourceSessionID,
                stableSessionID: stableID,
                line: parsed.line,
                timestamp: parsed.timestamp,
                now: now
            ) {
                turns.append(turn)
            } else {
                skippedRecordCount += 1
            }
        }

        // Uncertainty notes are derived only after every record has been
        // counted, so the durable coverage notes always agree with the
        // per-import ScanReport: unsupported response_item payloads counted
        // during turn building appear here exactly as they do in the scan.
        var uncertaintyNotes: [String] = []
        if malformedLineCount > 0 { uncertaintyNotes.append(Self.uncertaintyMalformedLines) }
        if skippedRecordCount > 0 { uncertaintyNotes.append(Self.uncertaintySkippedRecords) }

        let missingIdentity = sourceSessionID == nil
        let coverage = CoverageSummary.derived(
            from: turns,
            missingSessionIdentity: missingIdentity,
            parserVersion: Self.parserVersion,
            parserUncertaintyNotes: uncertaintyNotes
        )

        let startedAt: Date?
        if let sessionStartedAt {
            startedAt = sessionStartedAt
        } else {
            startedAt = coverage.firstRecordedAt
        }

        return NormalizationOutcome(
            session: NormalizedSession(
                stableID: stableID,
                sourceSessionID: sourceSessionID,
                title: title,
                project: project,
                startedAt: startedAt,
                startedAtApproximate: false,
                turns: turns,
                missingSessionIdentity: missingIdentity,
                coverage: coverage
            ),
            scan: ScanReport(recordLineCount: recordLineCount, malformedLineCount: malformedLineCount, skippedRecordCount: skippedRecordCount)
        )
    }

    /// Builds one turn from a `response_item` payload. Returns nil for
    /// payload types this parser does not retain as turns.
    private func turn(
        fromPayload payload: [String: Any],
        filePath: String,
        sourceSessionID: String?,
        stableSessionID: String,
        line: Int,
        timestamp: Date?,
        now: Date
    ) -> ConversationTurn? {
        let payloadType = payload["type"] as? String ?? ""
        let sourceTurnID = SessionIdentity.normalizedID(payload["id"] as? String)

        let role: ConversationRole
        let attribution: Attribution
        let note: String
        var selectedText = ""

        switch payloadType {
        case "message":
            let observedRole = payload["role"] as? String ?? "unknown"
            selectedText = Self.selectedText(from: payload["content"])
            switch observedRole {
            case "assistant":
                role = .assistant
                attribution = .agent
                note = "Observed role 'assistant' in transcript"
            case "user":
                role = .user
                attribution = .unclear
                note = "Observed role 'user' in transcript; user-role records can also carry tool-injected context, so this is not asserted as human authorship"
            case "system", "developer":
                role = .system
                attribution = .unclear
                note = "Observed role '\(observedRole)' in transcript"
            default:
                role = .unknown
                attribution = .unclear
                note = "Observed role '\(observedRole)' in transcript"
            }
        case "reasoning", "agent_reasoning":
            role = .reasoning
            attribution = .agent
            note = "Model reasoning step retained as observed agent output"
            selectedText = Self.selectedText(from: payload["content"])
        case "function_call", "local_shell_call", "custom_tool_call", "tool_call", "web_search_call":
            role = .tool
            attribution = .agent
            note = "Tool invocation issued by the agent"
            selectedText = payload["arguments"] as? String ?? ""
        case "function_call_output", "custom_tool_call_output", "tool_output":
            role = .tool
            attribution = .agent
            note = "Tool output returned to the agent"
            selectedText = payload["output"] as? String ?? ""
        default:
            return nil
        }

        let retainedTruncated = selectedText.count > limits.retainedTextCharacterLimit
        let retained = retainedTruncated ? String(selectedText.prefix(limits.retainedTextCharacterLimit)) : selectedText
        let approximate = timestamp == nil
        let preview = JSONParsing.cappedPreview(retained, limit: limits.previewCharacterLimit)
        let revision = TurnRevision(
            revisionID: SessionIdentity.revisionID(
                role: role,
                sourceTurnID: sourceTurnID,
                timestamp: timestamp,
                timestampApproximate: approximate,
                retainedText: retained
            ),
            importedAt: now,
            timestamp: timestamp,
            timestampApproximate: approximate,
            retainedText: retained,
            retainedTextTruncated: retainedTruncated,
            localPreview: preview,
            previewTruncated: retained.count > limits.previewCharacterLimit
        )

        return ConversationTurn(
            id: SessionIdentity.turnID(
                source: .codex,
                sourceSessionID: sourceSessionID,
                filePath: filePath,
                line: line,
                sourceTurnID: sourceTurnID
            ),
            sessionID: stableSessionID,
            role: role,
            sourceTurnID: sourceTurnID,
            sourcePath: filePath,
            sourceLine: line,
            sequence: 0,
            observedAttribution: attribution,
            observedAttributionNote: note,
            revisions: [revision]
        )
    }

    /// A source-established text field counts only when it is a non-empty
    /// string; missing titles/projects stay unknown and are never inferred.
    private static func sourceEstablishedText(_ raw: Any?) -> String? {
        guard let text = raw as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Collects readable text from the content shapes these rollout files
    /// use, without any preview cap. Retention capping happens at the turn
    /// boundary so it can be labeled.
    static func selectedText(from content: Any?) -> String {
        var parts: [String] = []
        switch content {
        case let text as String:
            parts.append(text)
        case let blocks as [[String: Any]]:
            for block in blocks {
                if let text = block["text"] as? String {
                    parts.append(text)
                } else if let input = block["input_text"] as? String {
                    parts.append(input)
                } else if let output = block["output_text"] as? String {
                    parts.append(output)
                }
            }
        default:
            break
        }
        return parts.joined(separator: " ")
    }
}
