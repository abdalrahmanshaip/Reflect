import Foundation
@testable import ReflectLib

struct PersistenceTests {
    static let suiteName = "PersistenceTests"

    private func sampleEvent(id: String = "ev-1") -> EvidenceEvent {
        EvidenceEvent(
            id: id,
            sourceKind: .claudeCode,
            sourceName: "Claude Code",
            timestamp: Date(timeIntervalSince1970: 1_767_603_600),
            timestampApproximate: true,
            kind: .userMessage,
            summary: "Synthetic event",
            detail: "Synthetic preview",
            evidencePath: "/tmp/fixture/session.jsonl",
            evidenceLine: 42,
            observedAttribution: .unclear,
            observedAttributionNote: "role in transcript",
            importedAt: Date(timeIntervalSince1970: 1_767_603_700)
        )
    }

    func eventsRoundTripPreservesAllFields() throws {
        let persistence = PersistenceController(directory: Fixtures.makeTempDirectory("events-rt"))
        let events = [sampleEvent(), sampleEvent(id: "ev-2")]
        try persistence.saveEvents(events)
        try expectEqual(try persistence.loadEvents(), events)
    }

    func settingsRoundTrip() throws {
        let persistence = PersistenceController(directory: Fixtures.makeTempDirectory("settings-rt"))
        var settings = AppSettings()
        settings.exclusions = ["alpha", "beta"]
        settings.aiEnabled = true
        settings.providerEndpoint = "https://api.example.com"
        settings.providerModel = "fixture-model"
        settings.pricePerMillionInput = 1.5
        settings.pricePerMillionOutput = 6.0
        settings.usageMode = .requested
        settings.gitRepositoryPath = "/tmp/fixture-repo"

        try persistence.saveSettings(settings)
        try expectEqual(try persistence.loadSettings(), settings)
    }

    func reportsRoundTripKeepsAnswers() throws {
        let persistence = PersistenceController(directory: Fixtures.makeTempDirectory("reports-rt"))
        let date = Date(timeIntervalSince1970: 1_767_603_600)
        var report = DailyReport(
            day: "2026-01-05",
            narrative: "Observed facts only.",
            narrativeGeneratedAt: date,
            answers: [:],
            analysisResult: nil,
            analysisGeneratedAt: nil,
            updatedAt: date
        )
        report.answers["2026-01-05-q1"] = AnswerEntry(text: "My own answer.", updatedAt: date)
        try persistence.saveReports([report])

        let loaded = try persistence.loadReports()
        try expectEqual(loaded, [report])
        try expectEqual(loaded.first?.answers["2026-01-05-q1"]?.text, "My own answer.")
    }

    func manifestsRoundTrip() throws {
        let persistence = PersistenceController(directory: Fixtures.makeTempDirectory("manifests-rt"))
        var manifests: [SourceKind: SourceManifest] = [
            .codex: SourceManifest(lastImport: Date(timeIntervalSince1970: 1_767_603_600), importedEventCount: 7, filesScanned: 1, note: nil)
        ]
        try persistence.saveManifests(manifests)
        try expectEqual(try persistence.loadManifests(), manifests)

        manifests[.claudeCode] = SourceManifest(lastImport: nil, importedEventCount: 0, filesScanned: 0, note: "Source not detected.")
        try persistence.saveManifests(manifests)
        try expectEqual(try persistence.loadManifests(), manifests)
    }

    func loadingMissingFilesYieldsEmptyDefaults() throws {
        let persistence = PersistenceController(directory: Fixtures.makeTempDirectory("fresh-rt"))
        try expectTrue(try persistence.loadEvents().isEmpty)
        try expectTrue(try persistence.loadCorrections().isEmpty)
        try expectTrue(try persistence.loadReports().isEmpty)
        try expectTrue(try persistence.loadManifests().isEmpty)
        try expectEqual(try persistence.loadSettings(), AppSettings.default())
    }

    static var entries: [TestEntry] {
        let tests = PersistenceTests()
        return [
            TestEntry(suite: suiteName, name: "eventsRoundTripPreservesAllFields") { try tests.eventsRoundTripPreservesAllFields() },
            TestEntry(suite: suiteName, name: "settingsRoundTrip") { try tests.settingsRoundTrip() },
            TestEntry(suite: suiteName, name: "reportsRoundTripKeepsAnswers") { try tests.reportsRoundTripKeepsAnswers() },
            TestEntry(suite: suiteName, name: "manifestsRoundTrip") { try tests.manifestsRoundTrip() },
            TestEntry(suite: suiteName, name: "loadingMissingFilesYieldsEmptyDefaults") { try tests.loadingMissingFilesYieldsEmptyDefaults() }
        ]
    }
}
