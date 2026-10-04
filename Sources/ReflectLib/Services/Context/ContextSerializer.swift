import Foundation

/// Renders bounded context items and the provider-bound document.
///
/// Privacy boundary, by construction:
/// - Renderings are built only from the item's structured fields and its
///   content text. Source paths, line locators, and store locations are
///   never inputs, so they can never be emitted.
/// - `containsSecretShape` conservatively detects common secret-shaped
///   strings (bearer/API tokens, private-key blocks, common cloud-key
///   shapes). Matching content is omitted from context entirely — never
///   redacted and never logged — by the retriever.
/// - `exceedsNoPrivateLocator` detects item text that happens to contain a
///   known private locator (for example, a path quoted inside a turn), so
///   such items can be omitted before they reach any envelope.
/// - Truncation cuts at UTF-8 character boundaries and appends an explicit
///   marker, so a truncated item is always labeled.
///
/// All detection shapes are exercised with synthetic sentinels only; no real
/// secret is ever used in tests or logs.
public struct ContextSerializer {
    /// Marker appended when an item was cut to fit the byte budget.
    static let truncationMarker = " …[truncated]"

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func iso(_ date: Date) -> String {
        iso8601.string(from: date)
    }

    public init() {}

    // MARK: Provider-bound item text

    /// The exact provider-bound text for one item: a provenance label line
    /// followed by the content text. The label carries role, observed
    /// attribution (kept exactly as recorded, with the ambiguity rule stated
    /// for unclear roles), observed time, and source display name — never
    /// paths or line locators.
    public func providerText(for item: ContextItem) -> String {
        let label: String
        switch item.kind {
        case .observedTurn:
            label = Self.observedLabel(
                heading: "observed turn",
                role: item.role?.rawValue,
                eventKindLabel: nil,
                attribution: item.observedAttribution,
                observedAt: item.observedAt,
                approximate: item.timestampApproximate,
                sourceKind: item.sourceKind,
                cappedAtImport: item.retainedTextCappedAtImport
            )
        case .observedEvent:
            label = Self.observedLabel(
                heading: "observed record",
                role: nil,
                eventKindLabel: item.eventKind?.label,
                attribution: item.observedAttribution,
                observedAt: item.observedAt,
                approximate: item.timestampApproximate,
                sourceKind: item.sourceKind,
                cappedAtImport: false
            )
        case .userCorrection:
            label = "[user correction — your explicit decision; the observed record above keeps its original attribution | record: \(item.sourceRecordID)]"
        case .selfReport:
            let day = item.dayKey ?? "unknown"
            label = "[self-report — your own saved answer; a report, not independently verified | day: \(day)]"
        }
        return label + "\n" + item.text
    }

    private static func observedLabel(
        heading: String,
        role: String?,
        eventKindLabel: String?,
        attribution: Attribution?,
        observedAt: Date?,
        approximate: Bool,
        sourceKind: SourceKind?,
        cappedAtImport: Bool
    ) -> String {
        var parts: [String] = [heading]
        if let role { parts.append("role: \(role)") }
        if let eventKindLabel { parts.append("type: \(eventKindLabel)") }
        if let attribution {
            let ambiguityNote = attribution == .unclear ? " — role does not prove human authorship" : ""
            parts.append("attribution: \(attribution.label)\(ambiguityNote) (observed)")
        }
        switch observedAt {
        case .some(let date):
            parts.append("time: \(iso(date))\(approximate ? " (approximate)" : "")")
        case nil:
            parts.append("time: unknown")
        }
        if let sourceKind { parts.append("source: \(sourceKind.displayName)") }
        if cappedAtImport { parts.append("retained text was capped at import") }
        return "[" + parts.joined(separator: " | ") + "]"
    }

    // MARK: Privacy screening

    /// Conservative secret-shaped-string detection over common token and key
    /// shapes: PEM private-key blocks, bearer tokens, `sk-`-style API keys,
    /// GitHub/AWS/Slack/Google/GitLab token shapes. Matching is
    /// case-insensitive by design (conservative). Tests exercise these with
    /// synthetic sentinels only.
    public static func containsSecretShape(_ text: String) -> Bool {
        secretExpressions.contains { $0.firstMatch(in: text, range: fullRange(text)) != nil }
    }

    private static let secretExpressions: [NSRegularExpression] = [
        "-----BEGIN [A-Z ]*PRIVATE KEY-----",
        "Bearer[ ]+[A-Za-z0-9_\\-.=+/]{16,}",
        "\\bsk-[A-Za-z0-9_\\-]{16,}",
        "\\bgh[pousr]_[A-Za-z0-9]{20,}",
        "\\bgithub_pat_[A-Za-z0-9_]{20,}",
        "\\bAKIA[0-9A-Z]{16,}\\b",
        "\\bxox[abprs]-[A-Za-z0-9\\-]{10,}",
        "\\bAIza[0-9A-Za-z_\\-]{30,}",
        "\\bglpat-[A-Za-z0-9_\\-]{16,}"
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    /// True when the text contains any of the given private locator strings
    /// (for example a source file path). Empty needles never match.
    public static func containsAnyPrivateLocator(_ text: String, locators: [String]) -> Bool {
        locators.contains { !$0.isEmpty && text.contains($0) }
    }

    private static func fullRange(_ text: String) -> NSRange {
        NSRange(text.startIndex..<text.endIndex, in: text)
    }

    // MARK: UTF-8-safe truncation

    /// Cuts the text to at most `maxBytes` UTF-8 encoded bytes without
    /// splitting a character. Returns the input unchanged when it already
    /// fits.
    public static func truncatingToUTF8ByteLimit(_ text: String, maxBytes: Int) -> String {
        guard maxBytes > 0 else { return "" }
        let bytes = Array(text.utf8)
        guard bytes.count > maxBytes else { return text }
        var cut = maxBytes
        while cut > 0, bytes[cut] & 0xC0 == 0x80 {
            cut -= 1
        }
        return String(decoding: bytes[0..<cut], as: UTF8.self)
    }

    // MARK: Provider-bound document

    /// The full provider-bound document for an envelope: schema, generation
    /// time, budget and coverage summary, earlier-example availability, date
    /// and source coverage, uncertainty notes, and the included items' exact
    /// provider-bound texts. Every line is either structural or already
    /// screened item text; nothing is logged anywhere.
    public func providerDocument(for envelope: ContextEnvelope) -> Data {
        var lines: [String] = []
        lines.append("Reflect bounded context (schema \(ContextEnvelope.schemaVersion))")
        lines.append("Generated: \(Self.iso(envelope.generatedAt))")

        let coverage = envelope.descriptor.coverage
        let budget = envelope.descriptor.budget
        lines.append(
            "Coverage: \(coverage.state.rawValue) — included \(coverage.includedItemCount) item(s), "
                + "\(coverage.includedByteCount) UTF-8 content bytes, \(coverage.includedTurnCount) turn(s); "
                + "omitted \(coverage.omittedItemCount); truncated \(coverage.truncatedItemCount)."
        )
        lines.append(
            "Budget: \(budget.maxItemCount) item(s), \(budget.maxByteCount) UTF-8 bytes, \(budget.maxTurnCount) turn(s) maximum."
        )
        switch envelope.earlierExamples {
        case .notRequested:
            lines.append("Earlier examples for comparison: not requested.")
        case .included(let count):
            lines.append("Earlier examples for comparison: \(count) included.")
        case .missing:
            lines.append("Earlier examples for comparison: none available.")
        case .notAssessable:
            lines.append("Earlier examples for comparison: not assessable from stored times.")
        }
        if let earliest = envelope.dateCoverage.earliest, let latest = envelope.dateCoverage.latest {
            let approximateNote = envelope.dateCoverage.includesApproximateOrMissingTimes
                ? " (some included times are approximate or missing)" : ""
            lines.append("Observed time coverage: \(Self.iso(earliest)) to \(Self.iso(latest))\(approximateNote).")
        } else {
            lines.append("Observed time coverage: no included record carries an observed time.")
        }
        if envelope.sourceKinds.isEmpty {
            lines.append("Sources included: none.")
        } else {
            lines.append("Sources included: " + envelope.sourceKinds.map(\.displayName).joined(separator: ", ") + ".")
        }
        if !envelope.uncertaintyNotes.isEmpty {
            lines.append("Notes:")
            envelope.uncertaintyNotes.forEach { lines.append("- \($0)") }
        }
        lines.append("Context items:")
        envelope.items.forEach { lines.append($0.text) }
        return Data(lines.joined(separator: "\n").utf8)
    }
}
