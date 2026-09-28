import Foundation

/// Turns one JSONL file into stable EvidenceEvents.
/// Lines without a parseable timestamp fall back to the file's modification date,
/// and are flagged `timestampApproximate`.
struct JSONLImportEngine {
    let importer: LineOrientedImporter
    let fileURL: URL
    let sourceName: String
    let maxPreviewCharacters: Int

    func run(now: Date = Date()) -> [EvidenceEvent] {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let fileModified = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date) ?? nil

        var events: [EvidenceEvent] = []
        var lineNumber = 0
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            lineNumber += 1
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard let record = importer.parse(line: line) else { continue }

            let approximate = record.timestamp == nil
            let timestamp = record.timestamp ?? fileModified ?? now
            let id = EvidenceIdentity.stableID(
                source: importer.sourceKind,
                path: fileURL.path,
                line: lineNumber,
                recordType: record.recordType
            )

            events.append(EvidenceEvent(
                id: id,
                sourceKind: importer.sourceKind,
                sourceName: sourceName,
                timestamp: timestamp,
                timestampApproximate: approximate,
                kind: record.kind,
                summary: record.summary,
                detail: JSONParsing.cappedPreview(record.detail, limit: maxPreviewCharacters),
                evidencePath: fileURL.path,
                evidenceLine: lineNumber,
                observedAttribution: record.observedAttribution,
                observedAttributionNote: record.observedAttributionNote,
                importedAt: now
            ))
        }
        return events
    }
}
