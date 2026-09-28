import Foundation
@testable import ReflectLib

struct AttributionCorrectionTests {
    static let suiteName = "AttributionCorrectionTests"

    private func makeEvent(observed: Attribution, id: String = "ev-1") -> EvidenceEvent {
        EvidenceEvent(
            id: id,
            sourceKind: .codex,
            sourceName: "Codex CLI",
            timestamp: Date(timeIntervalSince1970: 1_767_603_600),
            timestampApproximate: false,
            kind: .agentMessage,
            summary: "Synthetic event",
            detail: "",
            evidencePath: "/tmp/fixture/rollout.jsonl",
            evidenceLine: 2,
            observedAttribution: observed,
            observedAttributionNote: "role in transcript",
            importedAt: Date(timeIntervalSince1970: 1_767_603_700)
        )
    }

    func correctionOverridesObservedAttribution() throws {
        let event = makeEvent(observed: .agent)
        let corrections = [AttributionCorrection(eventId: event.id, attribution: .you, updatedAt: Date())]
        let resolved = AttributionResolver.resolve(event: event, corrections: corrections)
        try expectEqual(resolved.value, .you)
        try expectTrue(resolved.isCorrected)
    }

    func unclearCorrectionIsPreserved() throws {
        let event = makeEvent(observed: .agent)
        let corrections = [AttributionCorrection(eventId: event.id, attribution: .unclear, updatedAt: Date())]
        try expectEqual(AttributionResolver.resolve(event: event, corrections: corrections).value, .unclear)
    }

    func withoutCorrectionObservedStandsAndIsNotMarkedCorrected() throws {
        let event = makeEvent(observed: .agent)
        let resolved = AttributionResolver.resolve(event: event, corrections: [])
        try expectEqual(resolved.value, .agent)
        try expectFalse(resolved.isCorrected, "observed attribution must not be flagged as corrected")
    }

    func correctionsPersistIndependentlyOfEvents() throws {
        let dir = Fixtures.makeTempDirectory("correction-persistence")
        let persistence = PersistenceController(directory: dir)
        let event = makeEvent(observed: .agent)
        let correction = AttributionCorrection(eventId: event.id, attribution: .unclear, updatedAt: Date())

        try persistence.saveEvents([event])
        try persistence.saveCorrections([correction])

        let reloaded = PersistenceController(directory: dir)
        try expectEqual(try reloaded.loadEvents().count, 1)
        try expectEqual(try reloaded.loadCorrections().first?.attribution, .unclear)

        // Deleting the event must not delete the user's correction.
        try reloaded.saveEvents([])
        try expectEqual(try reloaded.loadCorrections().count, 1)
    }

    static var entries: [TestEntry] {
        let tests = AttributionCorrectionTests()
        return [
            TestEntry(suite: suiteName, name: "correctionOverridesObservedAttribution") { try tests.correctionOverridesObservedAttribution() },
            TestEntry(suite: suiteName, name: "unclearCorrectionIsPreserved") { try tests.unclearCorrectionIsPreserved() },
            TestEntry(suite: suiteName, name: "withoutCorrectionObservedStandsAndIsNotMarkedCorrected") { try tests.withoutCorrectionObservedStandsAndIsNotMarkedCorrected() },
            TestEntry(suite: suiteName, name: "correctionsPersistIndependentlyOfEvents") { try tests.correctionsPersistIndependentlyOfEvents() }
        ]
    }
}
