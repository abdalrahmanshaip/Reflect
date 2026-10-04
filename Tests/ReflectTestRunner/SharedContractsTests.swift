import Foundation
@testable import ReflectLib

struct SharedContractsTests {
    static let suiteName = "SharedContractsTests"

    // MARK: Synthetic helpers (never real activity)

    /// Encodes with sorted keys so the JSON text is deterministic, then decodes back.
    private func roundTrip<Value: Codable & Equatable>(_ value: Value) throws -> Value {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        return try JSONDecoder().decode(Value.self, from: data)
    }

    private func jsonString<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(data: try encoder.encode(value), encoding: .utf8) ?? ""
    }

    private func isStableDigestForm(_ value: String) -> Bool {
        value.count == 32 && value.allSatisfy { character in
            ("0"..."9").contains(character) || ("a"..."f").contains(character)
        }
    }

    /// A synthetic event whose ID is an opaque stable digest identity: the
    /// SHA-256-derived form used by `EvidenceIdentity` (32 lowercase hex
    /// characters), never a readable source/path/locator string.
    private func syntheticObservedEvent() -> EvidenceEvent {
        EvidenceEvent(
            id: "3f9c1d0b47a2e8c65b1d94f0a76c2e81",
            sourceKind: .codex,
            sourceName: "Synthetic codex fixture",
            timestamp: Date(timeIntervalSince1970: 1_767_225_600),
            timestampApproximate: false,
            kind: .userMessage,
            summary: "Synthetic user message",
            detail: "Synthetic fixture text used by tests only",
            evidencePath: "/tmp/reflect-synthetic/session.jsonl",
            evidenceLine: 7,
            observedAttribution: .agent,
            observedAttributionNote: "Structural import observation",
            importedAt: Date(timeIntervalSince1970: 1_767_225_601)
        )
    }

    // MARK: Claim provenance

    func claimProvenanceRoundTripsExactRawValues() throws {
        let expectedRawValues: [ClaimProvenance: String] = [
            .observed: "observed",
            .inferred: "inferred",
            .selfReport: "self_report",
            .userCorrection: "user_correction"
        ]
        try expectEqual(ClaimProvenance.allCases.count, 4, "provenance vocabulary has exactly four meanings")
        for (value, rawValue) in expectedRawValues {
            try expectEqual(value.rawValue, rawValue)
            try expectEqual(try roundTrip(value), value, "\(rawValue) must survive a Codable round trip unchanged")
            try expectTrue(try jsonString(value).contains("\"\(rawValue)\""), "encoded JSON must use the exact raw value \(rawValue)")
        }
        try expectTrue(try jsonString(ClaimProvenance.allCases).contains("\"user_correction\""), "no provenance case may encode outside the agreed vocabulary")
    }

    // MARK: Claim confidence

    func claimConfidenceRoundTripsExactRawValuesAndOrder() throws {
        let expectedRawValues: [ClaimConfidence: String] = [
            .insufficientEvidence: "insufficient_evidence",
            .low: "low",
            .moderate: "moderate",
            .high: "high"
        ]
        try expectEqual(ClaimConfidence.allCases.count, 4, "confidence vocabulary has exactly four states")
        for (value, rawValue) in expectedRawValues {
            try expectEqual(value.rawValue, rawValue)
            try expectEqual(try roundTrip(value), value, "\(rawValue) must survive a Codable round trip unchanged")
            try expectTrue(try jsonString(value).contains("\"\(rawValue)\""), "encoded JSON must use the exact raw value \(rawValue)")
        }
        try expectTrue(ClaimConfidence.insufficientEvidence < .low, "insufficient evidence is below the assessable range")
        try expectTrue(ClaimConfidence.low < .moderate, "low must order below moderate")
        try expectTrue(ClaimConfidence.moderate < .high, "moderate must order below high")
    }

    // MARK: Capability availability

    func capabilityAvailabilityRoundTripsExactRawValues() throws {
        let expectedRawValues: [CapabilityAvailability: String] = [
            .available: "available",
            .unavailable: "unavailable",
            .unverified: "unverified",
            .disabled: "disabled"
        ]
        try expectEqual(CapabilityAvailability.allCases.count, 4, "capability vocabulary has exactly four states")
        for (value, rawValue) in expectedRawValues {
            try expectEqual(value.rawValue, rawValue)
            try expectEqual(try roundTrip(value), value, "\(rawValue) must survive a Codable round trip unchanged")
            try expectTrue(try jsonString(value).contains("\"\(rawValue)\""), "encoded JSON must use the exact raw value \(rawValue)")
        }
        try expectEqual(Set(CapabilityAvailability.allCases.map(\.rawValue)).count, 4, "every capability state needs a distinct raw value")
        try expectNotEqual(CapabilityAvailability.available, .unverified, "detected does not imply verified")
    }

    // MARK: Store identity and schema version

    func storeFileNameAndSchemaVersionMappingIsStable() throws {
        let expectedFileNames: [StoreName: String] = [
            .events: "events.json",
            .corrections: "corrections.json",
            .reports: "reports.json",
            .settings: "settings.json",
            .manifests: "manifests.json",
            .sessions: "sessions.json",
            .conversations: "conversations.json"
        ]
        try expectEqual(StoreName.allCases.count, 7, "Reflect persists exactly seven JSON stores")
        for (store, fileName) in expectedFileNames {
            try expectEqual(store.fileName, fileName, "\(store.rawValue) must keep its stable file name")
            try expectEqual(store.schemaVersion, 1, "\(store.rawValue) is currently at schema version 1")
        }
    }

    // MARK: Correction separation

    func userCorrectionStaysSeparateFromUnchangedObservedAttribution() throws {
        let event = syntheticObservedEvent()
        let correction = AttributionCorrection(
            eventId: event.id,
            attribution: .you,
            updatedAt: Date(timeIntervalSince1970: 1_767_225_602)
        )

        // The correction is its own record: applying it never mutates the observation.
        let resolved = AttributionResolver.resolve(event: event, corrections: [correction])
        try expectEqual(resolved.value, Attribution.you)
        try expectEqual(resolved.isCorrected, true)
        try expectEqual(event.observedAttribution, Attribution.agent, "the observed attribution must remain unchanged by the correction")
        try expectEqual(event.observedAttributionNote, "Structural import observation", "the observation's own note must remain unchanged")

        // Persisted separately, both records round trip without bleeding into each other.
        let decodedEvent = try roundTrip(event)
        let decodedCorrection = try roundTrip(correction)
        try expectEqual(decodedEvent.observedAttribution, Attribution.agent)
        try expectEqual(decodedCorrection.attribution, Attribution.you)
        try expectNotEqual(decodedEvent.observedAttribution, decodedCorrection.attribution, "correction and observation must remain distinct records after persistence")

        // The resolved attribution changes only through the separate correction record.
        try expectEqual(AttributionResolver.resolve(event: decodedEvent, corrections: []).value, Attribution.agent, "without the correction record the observed value stands")
    }

    // MARK: Existing record identity compatibility

    func existingRecordIdentitiesRemainSourceCompatible() throws {
        let event = syntheticObservedEvent()
        let report = DailyReport(
            day: "2026-01-11",
            narrative: "Synthetic narrative",
            narrativeGeneratedAt: nil,
            answers: [:],
            analysisResult: nil,
            analysisGeneratedAt: nil,
            updatedAt: Date(timeIntervalSince1970: 1_767_225_603)
        )
        let correction = AttributionCorrection(
            eventId: event.id,
            attribution: .unclear,
            updatedAt: Date(timeIntervalSince1970: 1_767_225_604)
        )

        // Imported evidence IDs are opaque stable digests: 32 lowercase hex
        // characters derived from the source-locator key, never readable paths.
        try expectEqual(event.id, "3f9c1d0b47a2e8c65b1d94f0a76c2e81")
        try expectTrue(isStableDigestForm(event.id), "evidence ID must be an opaque 32-character lowercase hex digest")

        // The real identity function produces the same stable digest form deterministically.
        let derived = EvidenceIdentity.stableID(source: .codex, path: "/tmp/reflect-synthetic/session.jsonl", line: 7, recordType: "user_message")
        let derivedAgain = EvidenceIdentity.stableID(source: .codex, path: "/tmp/reflect-synthetic/session.jsonl", line: 7, recordType: "user_message")
        try expectEqual(derived, derivedAgain, "the same source record must produce the same stable ID")
        try expectTrue(isStableDigestForm(derived), "stable ID must be an opaque 32-character lowercase hex digest")

        // Report identity stays its day key; correction identity stays its event ID.
        try expectEqual(report.id, "2026-01-11")
        try expectEqual(correction.id, event.id)
        // App-owned new records may use plain UUID strings: same String ID type, no wrapper.
        let appOwnedID = UUID().uuidString
        try expectEqual(String(describing: appOwnedID), appOwnedID)
        try expectTrue(!appOwnedID.isEmpty)
    }
}

extension SharedContractsTests {
    static var entries: [TestEntry] {
        let tests = SharedContractsTests()
        return [
            TestEntry(suite: suiteName, name: "claimProvenanceRoundTripsExactRawValues") {
                try tests.claimProvenanceRoundTripsExactRawValues()
            },
            TestEntry(suite: suiteName, name: "claimConfidenceRoundTripsExactRawValuesAndOrder") {
                try tests.claimConfidenceRoundTripsExactRawValuesAndOrder()
            },
            TestEntry(suite: suiteName, name: "capabilityAvailabilityRoundTripsExactRawValues") {
                try tests.capabilityAvailabilityRoundTripsExactRawValues()
            },
            TestEntry(suite: suiteName, name: "storeFileNameAndSchemaVersionMappingIsStable") {
                try tests.storeFileNameAndSchemaVersionMappingIsStable()
            },
            TestEntry(suite: suiteName, name: "userCorrectionStaysSeparateFromUnchangedObservedAttribution") {
                try tests.userCorrectionStaysSeparateFromUnchangedObservedAttribution()
            },
            TestEntry(suite: suiteName, name: "existingRecordIdentitiesRemainSourceCompatible") {
                try tests.existingRecordIdentitiesRemainSourceCompatible()
            }
        ]
    }
}
