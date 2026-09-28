import Foundation
import Combine

/// Main app state. Lives on the main actor; imports run detached and hop back.
@MainActor
public final class AppStore: ObservableObject {
    @Published public private(set) var events: [EvidenceEvent] = []
    @Published public private(set) var corrections: [AttributionCorrection] = []
    @Published public private(set) var reports: [DailyReport] = []
    @Published public var settings: AppSettings = .default()
    @Published public private(set) var manifests: [SourceKind: SourceManifest] = [:]
    @Published public private(set) var availability: [SourceKind: SourceAvailability] = [:]
    @Published public private(set) var importing: Set<SourceKind> = []
    @Published public var lastError: String?
    @Published public private(set) var lastImportSummary: String?

    private let persistence: PersistenceController
    let secrets: SecretStore
    private let home: URL

    public convenience init() {
        self.init(
            persistence: PersistenceController(directory: PersistenceController.defaultDirectory()),
            secrets: KeychainSecretStore(),
            home: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    init(
        persistence: PersistenceController,
        secrets: SecretStore,
        home: URL
    ) {
        self.persistence = persistence
        self.secrets = secrets
        self.home = home
        loadAll()
        refreshAvailability()
    }

    // MARK: Persistence

    func loadAll() {
        events = (try? persistence.loadEvents()) ?? []
        events.sort { $0.timestamp > $1.timestamp }
        corrections = (try? persistence.loadCorrections()) ?? []
        reports = (try? persistence.loadReports()) ?? []
        settings = (try? persistence.loadSettings()) ?? .default()
        manifests = (try? persistence.loadManifests()) ?? [:]
    }

    func persistEvents() {
        do { try persistence.saveEvents(events) } catch { lastError = "Saving events failed: \(error.localizedDescription)" }
    }

    func persistCorrections() {
        do { try persistence.saveCorrections(corrections) } catch { lastError = "Saving corrections failed: \(error.localizedDescription)" }
    }

    func persistReports() {
        do { try persistence.saveReports(reports) } catch { lastError = "Saving reports failed: \(error.localizedDescription)" }
    }

    func persistSettings() {
        do { try persistence.saveSettings(settings) } catch { lastError = "Saving settings failed: \(error.localizedDescription)" }
    }

    func persistManifests() {
        do { try persistence.saveManifests(manifests) } catch { lastError = "Saving import state failed: \(error.localizedDescription)" }
    }

    // MARK: Availability (metadata only; never reads contents)

    public func refreshAvailability() {
        let scanner = SourceScanner(home: home)
        for kind in SourceKind.allCases {
            availability[kind] = scanner.availability(for: kind, settings: settings)
        }
    }

    // MARK: Import (explicit user action only)

    func importSource(_ kind: SourceKind) {
        guard !importing.contains(kind) else { return }
        importing.insert(kind)
        let currentSettings = settings
        let currentHome = home
        Task.detached(priority: .userInitiated) {
            let outcome = ImportOrchestrator.importSource(kind: kind, home: currentHome, settings: currentSettings)
            await self.finishImport(outcome)
        }
    }

    func importAllAvailable() {
        for kind in SourceKind.allCases {
            if kind == .gitLocal && (settings.gitRepositoryPath ?? "").isEmpty { continue }
            importSource(kind)
        }
    }

    private func finishImport(_ outcome: ImportOutcome) {
        importing.remove(outcome.kind)

        let result = EventDeduplicator.merge(existing: events, incoming: outcome.events)
        events = result.merged.sorted { $0.timestamp > $1.timestamp }
        persistEvents()

        var manifest = manifests[outcome.kind] ?? SourceManifest(lastImport: nil, importedEventCount: 0, filesScanned: 0, note: nil)
        manifest.lastImport = Date()
        manifest.filesScanned = outcome.filesScanned
        manifest.importedEventCount = events.filter { $0.sourceKind == outcome.kind }.count
        manifest.note = outcome.note
        manifests[outcome.kind] = manifest
        persistManifests()
        refreshAvailability()

        if let note = outcome.note {
            lastImportSummary = "\(outcome.kind.displayName): \(note)"
        } else {
            lastImportSummary = "\(outcome.kind.displayName): \(result.added) new event(s) added, \(outcome.filesScanned) file(s) scanned."
        }
    }

    // MARK: Attribution

    func effectiveAttribution(for event: EvidenceEvent) -> (value: Attribution, isCorrected: Bool) {
        AttributionResolver.resolve(event: event, corrections: corrections)
    }

    func setCorrection(_ attribution: Attribution?, for eventId: String) {
        corrections.removeAll { $0.eventId == eventId }
        if let attribution {
            corrections.append(AttributionCorrection(eventId: eventId, attribution: attribution, updatedAt: Date()))
        }
        persistCorrections()
        objectWillChange.send()
    }

    // MARK: Reports

    func report(for dayKey: String) -> DailyReport {
        if let existing = reports.first(where: { $0.day == dayKey }) {
            return existing
        }
        return DailyReport(
            day: dayKey,
            narrative: "",
            narrativeGeneratedAt: nil,
            answers: [:],
            analysisResult: nil,
            analysisGeneratedAt: nil,
            updatedAt: Date()
        )
    }

    func saveReport(_ report: DailyReport) {
        var updated = report
        updated.updatedAt = Date()
        if let index = reports.firstIndex(where: { $0.day == report.day }) {
            reports[index] = updated
        } else {
            reports.append(updated)
        }
        persistReports()
    }

    // MARK: Derived views

    func events(onDay dayKey: String) -> [EvidenceEvent] {
        events.filter { Fmt.dayKey($0.timestamp) == dayKey }
    }

    func dayFacts(for dayKey: String) -> DayFacts {
        let dayEventIDs = Set(events(onDay: dayKey).map(\.id))
        let applied = corrections.filter { dayEventIDs.contains($0.eventId) }.count
        return DayFacts(dayKey: dayKey, events: events(onDay: dayKey), correctionsApplied: applied)
    }

    func growthSummary() -> GrowthSummary {
        GrowthAnalyzer.summarize(events: events, corrections: corrections)
    }

    func allDayKeys() -> [String] {
        Array(Set(events.map { Fmt.dayKey($0.timestamp) })).sorted(by: >)
    }

    func countBySource(for dayEvents: [EvidenceEvent]) -> [(SourceKind, Int)] {
        let grouped = Dictionary(grouping: dayEvents, by: \.sourceKind)
        return SourceKind.allCases.compactMap { kind in
            guard let count = grouped[kind]?.count, count > 0 else { return nil }
            return (kind, count)
        }.sorted { $0.1 > $1.1 }
    }

    // MARK: AI secrets

    func hasAPIKey() -> Bool {
        let value = secrets.secret(account: AppConstants.keychainAccount)
        return value?.isEmpty == false
    }

    func setAPIKey(_ value: String) {
        do {
            try secrets.setSecret(value, account: AppConstants.keychainAccount)
            lastError = nil
        } catch {
            lastError = "Storing the API key failed: \(error.localizedDescription)"
        }
    }

    func deleteAPIKey() {
        do {
            try secrets.deleteSecret(account: AppConstants.keychainAccount)
        } catch {
            lastError = "Deleting the API key failed: \(error.localizedDescription)"
        }
    }

    func aiStatus() -> AnalysisService.Status {
        AnalysisService.status(settings: settings, hasKey: hasAPIKey())
    }

    // MARK: Data folder

    var dataDirectory: URL { persistence.directory }
}
