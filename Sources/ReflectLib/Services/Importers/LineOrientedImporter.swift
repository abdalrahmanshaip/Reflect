import Foundation

/// One parsed record from a line-oriented source, before it becomes an EvidenceEvent.
struct ImportedRecord {
    let timestamp: Date?
    let kind: EventKind
    let observedAttribution: Attribution
    let observedAttributionNote: String
    let summary: String
    let detail: String
    let recordType: String
}

/// A tolerant adapter for one line-oriented source format.
protocol LineOrientedImporter {
    var sourceKind: SourceKind { get }
    var sourceName: String { get }
    func matches(fileName: String) -> Bool
    func parse(line: String) -> ImportedRecord?
}
