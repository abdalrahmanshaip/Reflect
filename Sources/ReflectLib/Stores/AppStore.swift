import Foundation
import Combine

/// Main app state. Lives on the main actor; imports run detached and hop back.
@MainActor
public final class AppStore: ObservableObject {
    @Published public private(set) var events: [EvidenceEvent] = []
    @Published public private(set) var corrections: [AttributionCorrection] = []
    @Published public private(set) var reports: [DailyReport] = []
    @Published public private(set) var settings: AppSettings = .default()
    @Published public private(set) var manifests: [SourceKind: SourceManifest] = [:]
    @Published public private(set) var availability: [SourceKind: SourceAvailability] = [:]
    @Published public private(set) var analysisAgents: [AnalysisAgentStatus] = []
    /// True while an agent availability check is in flight. Settings renders
    /// immediately and shows a checking state before any result exists.
    @Published public private(set) var isCheckingAnalysisAgents = false
    /// When the last completed (uncanceled) availability check finished.
    /// Retained while a later refresh is pending so the UI can show how old
    /// the visible statuses are.
    @Published public private(set) var analysisAgentsLastChecked: Date?
    @Published public private(set) var importing: Set<SourceKind> = []
    /// Keyed per-source outcomes. Every source that actually ran keeps its own
    /// result here, so one completion never erases another source's outcome —
    /// regardless of completion order. Messages are safe: source names,
    /// counts, and status only.
    @Published public private(set) var importResults: [SourceKind: ImportSourceResult] = [:]
    @Published public private(set) var hasStoredAPIKey: Bool = false
    @Published public var lastError: String?
    @Published public private(set) var lastImportSummary: String?
    @Published public private(set) var eventIndex = EventProjectionIndex(events: [])
    /// Per-store read/decode failures. A store listed here blocks its own
    /// ordinary writes until an explicit recovery succeeds.
    @Published public private(set) var storeFailures: [StoreName: StoreFailure] = [:]
    /// Safe message from the most recent failed recovery attempt; cleared on success.
    @Published public private(set) var lastRecoveryMessage: String?

    private let persistence: PersistenceController
    /// Agent availability provider. Discovery runs process work away from the
    /// main actor and publishes results on it; inject a fake for fixtures and
    /// tests so no real CLI is ever invoked.
    private let analysisAvailabilityProvider: @Sendable () async -> [AnalysisAgentStatus]
    /// The import work boundary. Defaults to the real local, read-only
    /// orchestrator; tests inject a recording fake to prove which sources ever
    /// reach the content-reading executor.
    private let importExecutor: ImportSourceExecutor
    let secrets: SecretStore
    private let home: URL
    private var analysisCheckGeneration: UUID?
    private var analysisCheckTask: Task<Void, Never>?
    private var analysisCheckQueued = false

    public convenience init() {
        self.init(
            persistence: PersistenceController(directory: PersistenceController.defaultDirectory()),
            secrets: KeychainSecretStore(),
            home: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    /// Full initializer for explicit store locations — used by the app and by the
    /// test-only synthetic UI launcher, which points everything at temporary fixtures.
    public init(
        persistence: PersistenceController,
        secrets: SecretStore,
        home: URL,
        analysisAvailabilityProvider: (@Sendable () async -> [AnalysisAgentStatus])? = nil,
        importExecutor: ImportSourceExecutor? = nil
    ) {
        self.persistence = persistence
        self.analysisAvailabilityProvider = analysisAvailabilityProvider ?? {
            await AnalysisAgentDiscovery().discover()
        }
        self.importExecutor = importExecutor ?? { kind, home, settings in
            ImportOrchestrator.importSource(kind: kind, home: home, settings: settings)
        }
        self.secrets = secrets
        self.home = home
        loadAll()
        refreshAvailability()
    }

    /// Candidate-based store writes (Task B): each helper persists the given
    /// candidate and reports success. Callers publish the candidate only when
    /// the write succeeded, so published state never diverges from disk.

    @discardableResult
    private func writeEvents(_ candidate: [EvidenceEvent]) -> Bool {
        guard storeFailures[.events] == nil else {
            lastError = StoreHealthMessages.saveBlocked(.events)
            return false
        }
        do {
            try persistence.saveEvents(candidate)
            return true
        } catch {
            lastError = StoreHealthMessages.saveFailed(.events)
            return false
        }
    }

    @discardableResult
    private func writeCorrections(_ candidate: [AttributionCorrection]) -> Bool {
        guard storeFailures[.corrections] == nil else {
            lastError = StoreHealthMessages.saveBlocked(.corrections)
            return false
        }
        do {
            try persistence.saveCorrections(candidate)
            return true
        } catch {
            lastError = StoreHealthMessages.saveFailed(.corrections)
            return false
        }
    }

    @discardableResult
    private func writeReports(_ candidate: [DailyReport]) -> Bool {
        guard storeFailures[.reports] == nil else {
            lastError = StoreHealthMessages.saveBlocked(.reports)
            return false
        }
        do {
            try persistence.saveReports(candidate)
            return true
        } catch {
            lastError = StoreHealthMessages.saveFailed(.reports)
            return false
        }
    }

    @discardableResult
    private func writeSettings(_ candidate: AppSettings) -> Bool {
        guard storeFailures[.settings] == nil else {
            lastError = StoreHealthMessages.saveBlocked(.settings)
            return false
        }
        do {
            try persistence.saveSettings(candidate)
            return true
        } catch {
            lastError = StoreHealthMessages.saveFailed(.settings)
            return false
        }
    }

    @discardableResult
    private func writeManifests(_ candidate: [SourceKind: SourceManifest]) -> Bool {
        guard storeFailures[.manifests] == nil else {
            lastError = StoreHealthMessages.saveBlocked(.manifests)
            return false
        }
        do {
            try persistence.saveManifests(candidate)
            return true
        } catch {
            lastError = StoreHealthMessages.saveFailed(.manifests)
            return false
        }
    }

    // MARK: Persistence

    func loadAll() {
        events = accepted(load: persistence.loadEventsHealth(), store: .events, default: [])
            .sorted { $0.timestamp > $1.timestamp }
        eventIndex = EventProjectionIndex(events: events)
        corrections = accepted(load: persistence.loadCorrectionsHealth(), store: .corrections, default: [])
        reports = accepted(load: persistence.loadReportsHealth(), store: .reports, default: [])
        settings = accepted(load: persistence.loadSettingsHealth(), store: .settings, default: .default())
        manifests = accepted(load: persistence.loadManifestsHealth(), store: .manifests, default: [:])
    }

    /// Only a genuinely absent store may load as the first-run default. A
    /// failed load keeps its default in memory for display, but the failure is
    /// recorded so the store's own writes are blocked until explicit recovery.
    private func accepted<Value>(load: StoreLoad<Value>, store: StoreName, default defaultValue: Value) -> Value {
        switch load {
        case .missing:
            storeFailures[store] = nil
            return defaultValue
        case .loaded(let value):
            storeFailures[store] = nil
            return value
        case .failed(let failure):
            storeFailures[store] = failure
            return defaultValue
        }
    }

    /// Persists the currently published value of each store. These remain for
    /// reload-style flows; mutation flows must persist a candidate and publish
    /// it only on success.
    func persistEvents() { _ = writeEvents(events) }

    func persistCorrections() { _ = writeCorrections(corrections) }

    func persistSettings() { _ = writeSettings(settings) }

    func persistManifests() { _ = writeManifests(manifests) }

    // MARK: Availability (metadata only; never reads contents)

    public func refreshAvailability() {
        let scanner = SourceScanner(home: home)
        for kind in SourceKind.allCases {
            availability[kind] = scanner.availability(for: kind, settings: settings)
        }
    }

    /// Checks only the supported CLIs' documented local auth-status commands.
    /// It never starts an analysis run and never reads Reflect evidence.
    ///
    /// Explicit user action (Refresh button or command). Overlapping requests
    /// coalesce: while a check is in flight at most one follow-up run is
    /// queued, so process work never overlaps and repeated clicks collapse.
    public func refreshAnalysisAvailability() {
        guard analysisCheckGeneration == nil else {
            analysisCheckQueued = true
            return
        }
        startAnalysisCheck()
    }

    /// Appearance-driven check: runs once, until a first completed result
    /// exists. Opening Settings again after a completed check never launches
    /// another process; the retained result and last-checked time stay visible.
    public func ensureAnalysisAvailabilityChecked() {
        guard analysisAgents.isEmpty, analysisCheckGeneration == nil else { return }
        startAnalysisCheck()
    }

    /// Stops the pending check, if any. Cancellation is cooperative: the
    /// runner terminates (and force-kills, if needed) the active subprocess
    /// and no stale or partial result is published. Never blocks navigation,
    /// focusing, or closing Settings.
    public func cancelAnalysisAvailabilityCheck() {
        guard analysisCheckGeneration != nil else { return }
        analysisCheckGeneration = nil
        analysisCheckQueued = false
        isCheckingAnalysisAgents = false
        analysisCheckTask?.cancel()
        analysisCheckTask = nil
    }

    private func startAnalysisCheck() {
        guard analysisCheckGeneration == nil else { return }
        isCheckingAnalysisAgents = true
        let generation = UUID()
        analysisCheckGeneration = generation
        let provider = analysisAvailabilityProvider
        analysisCheckTask = Task(priority: .userInitiated) {
            // The provider is a nonisolated async function: discovery and its
            // process work run away from the main actor; the completion below
            // runs on the main actor and publishes there.
            let statuses = await provider()
            finishAnalysisCheck(statuses, generation: generation)
        }
    }

    private func finishAnalysisCheck(_ statuses: [AnalysisAgentStatus], generation: UUID) {
        guard analysisCheckGeneration == generation else { return }
        analysisCheckGeneration = nil
        analysisCheckTask = nil
        analysisAgents = statuses
        analysisAgentsLastChecked = Date()
        isCheckingAnalysisAgents = false
        if analysisCheckQueued {
            analysisCheckQueued = false
            startAnalysisCheck()
        }
    }

    // MARK: Import (explicit user action only)

    /// One explicit source request. The eligibility decision is checked here,
    /// at the scheduling boundary, so a disabled or unverified source can
    /// never schedule adapter or content-reading work, no matter which button
    /// sent the request.
    func importSource(_ kind: SourceKind) {
        guard isEligible(kind: kind, scope: .singleSource) else { return }
        scheduleImport(kind)
    }

    /// Bulk scheduling uses the same one eligibility decision in bulk scope:
    /// only enabled, verified, not-already-importing sources with detected
    /// availability are scheduled, and Git additionally requires an explicitly
    /// selected repository. Missing, disabled, and unverified sources are
    /// never scanned or read.
    func importAllAvailable() {
        for kind in SourceKind.allCases {
            guard isEligible(kind: kind, scope: .bulkImport) else { continue }
            scheduleImport(kind)
        }
    }

    private func isEligible(kind: SourceKind, scope: ImportRules.SchedulingScope) -> Bool {
        ImportRules.isImportEligible(
            kind: kind,
            scope: scope,
            importing: importing,
            enabledSources: settings.enabledSources,
            gitRepositoryPath: settings.gitRepositoryPath,
            formatVerified: kind.formatVerified,
            availability: availability[kind]
        )
    }

    private func scheduleImport(_ kind: SourceKind) {
        importing.insert(kind)
        let currentSettings = settings
        let currentHome = home
        let executor = importExecutor
        Task.detached(priority: .userInitiated) {
            let outcome = await executor(kind, currentHome, currentSettings)
            await self.finishImport(outcome)
        }
    }

    private func finishImport(_ outcome: ImportOutcome) {
        importing.remove(outcome.kind)

        let result = EventDeduplicator.merge(existing: events, incoming: outcome.events)
        let eventsCandidate = result.merged.sorted { $0.timestamp > $1.timestamp }

        // Task B (narrow integrity fix): the import is only durable once the
        // events write succeeds. On failure the previously published events
        // and manifest stay untouched, the found records stay retryable
        // through the Import button, and the failure is retained in this
        // source's keyed result.
        guard writeEvents(eventsCandidate) else {
            let failure = ImportSourceResult.eventWriteFailed(kind: outcome.kind, addedCount: result.added)
            importResults[outcome.kind] = failure
            lastImportSummary = failure.message
            return
        }
        events = eventsCandidate
        eventIndex = EventProjectionIndex(events: events)

        var manifest = manifests[outcome.kind] ?? SourceManifest(lastImport: nil, importedEventCount: 0, filesScanned: 0, note: nil)
        manifest.lastImport = Date()
        manifest.filesScanned = outcome.filesScanned
        manifest.importedEventCount = events.filter { $0.sourceKind == outcome.kind }.count
        manifest.note = outcome.note
        var manifestsCandidate = manifests
        manifestsCandidate[outcome.kind] = manifest
        let manifestAdvanced = writeManifests(manifestsCandidate)
        if manifestAdvanced {
            manifests = manifestsCandidate
        }
        refreshAvailability()

        // Keyed per-source result (Task E): both durable outcomes stay honest.
        // Saved events stay published even when the manifest could not advance,
        // and the result never claims the manifest advanced when it did not.
        let summary = ImportSourceResult.completed(
            kind: outcome.kind,
            addedCount: result.added,
            filesScanned: outcome.filesScanned,
            note: outcome.note,
            manifestAdvanced: manifestAdvanced
        )
        importResults[outcome.kind] = summary
        lastImportSummary = summary.message
    }

    // MARK: Attribution

    func effectiveAttribution(for event: EvidenceEvent) -> (value: Attribution, isCorrected: Bool) {
        AttributionResolver.resolve(event: event, corrections: corrections)
    }

    func setCorrection(_ attribution: Attribution?, for eventId: String) {
        var candidate = corrections
        candidate.removeAll { $0.eventId == eventId }
        if let attribution {
            candidate.append(AttributionCorrection(eventId: eventId, attribution: attribution, updatedAt: Date()))
        }
        guard writeCorrections(candidate) else { return }
        corrections = candidate
        objectWillChange.send()
    }

    // MARK: Settings updates

    /// Persists the transformed settings candidate and publishes it only when
    /// the write succeeds, so a failed preference change can never stay
    /// visible while disk holds the old value. Returns whether the change is
    /// both saved and published; on failure the caller's control re-reads the
    /// published value and the error surfaces through `lastError`.
    @discardableResult
    public func updateSettings(_ transform: (inout AppSettings) -> Void) -> Bool {
        var candidate = settings
        transform(&candidate)
        guard writeSettings(candidate) else { return false }
        settings = candidate
        return true
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

    /// Persists the report and reports whether the write succeeded, so views can
    /// show honest save states instead of claiming success unconditionally.
    /// Task B: the candidate collection is persisted first and published only
    /// on success, so a rejected save never leaves the report collection — or
    /// any reflected status derived from it — claiming unsaved state as saved.
    /// A rejected save also leaves the user's draft untouched for an explicit
    /// retry through the same call.
    @discardableResult
    func saveReport(_ report: DailyReport) -> Bool {
        var updated = report
        updated.updatedAt = Date()
        var candidate = reports
        if let index = candidate.firstIndex(where: { $0.day == report.day }) {
            candidate[index] = updated
        } else {
            candidate.append(updated)
        }
        guard writeReports(candidate) else { return false }
        reports = candidate
        return true
    }

    // MARK: Derived views

    func events(onDay dayKey: String) -> [EvidenceEvent] {
        eventIndex.events(onDay: dayKey, from: events)
    }

    func todayProjection(for dayKey: String) -> TodayRouteProjection {
        let dayEvents = events(onDay: dayKey)
        let report = reports.first { $0.day == dayKey }
        return RouteProjectionBuilder.today(
            dayKey: dayKey,
            events: dayEvents,
            report: report,
            corrections: corrections
        )
    }

    func dayOverview(for dayKey: String) -> DayOverview {
        let dayEvents = events(onDay: dayKey)
        let dayEventIDs = Set(dayEvents.map(\.id))
        let dayCorrections = corrections.filter { dayEventIDs.contains($0.eventId) }
        return DayOverviewBuilder.overview(
            dayKey: dayKey,
            events: dayEvents,
            report: reports.first { $0.day == dayKey },
            corrections: dayCorrections
        )
    }

    func timelineProjection(
        dayKey: String?,
        source: SourceKind?,
        kind: EventKind?
    ) -> TimelineProjection {
        RouteProjectionBuilder.timeline(
            events: events,
            index: eventIndex,
            dayKey: dayKey,
            source: source,
            kind: kind
        )
    }

    func weeklyProjection(referenceDate: Date) -> WeeklyRouteProjection {
        RouteProjectionBuilder.weekly(referenceDate: referenceDate, events: events, index: eventIndex)
    }

    func eventCount(onDay dayKey: String) -> Int {
        eventIndex.count(onDay: dayKey)
    }

    func recentDays(limit: Int = 8) -> [RecentDay] {
        DayOverviewBuilder.recentDays(index: eventIndex, reports: reports, limit: limit)
    }

    func dayFacts(for dayKey: String) -> DayFacts {
        let dayEventIDs = Set(events(onDay: dayKey).map(\.id))
        let applied = corrections.filter { dayEventIDs.contains($0.eventId) }.count
        return DayFacts(dayKey: dayKey, events: events(onDay: dayKey), correctionsApplied: applied)
    }

    func growthSummary() -> GrowthSummary {
        GrowthAnalyzer.summarize(events: events, corrections: corrections, index: eventIndex)
    }

    func allDayKeys() -> [String] {
        eventIndex.dayKeys
    }

    func countBySource(for dayEvents: [EvidenceEvent]) -> [(SourceKind, Int)] {
        let grouped = Dictionary(grouping: dayEvents, by: \.sourceKind)
        return SourceKind.allCases.compactMap { kind in
            guard let count = grouped[kind]?.count, count > 0 else { return nil }
            return (kind, count)
        }.sorted { $0.1 > $1.1 }
    }

    // MARK: AI secrets

    /// Legacy compatibility hook. The current agent workflow does not call it
    /// during store creation, Settings appearance, or route selection; an
    /// explicit legacy caller may still refresh the old key presence state.
    func refreshKeyPresence() {
        hasStoredAPIKey = secrets.secret(account: AppConstants.keychainAccount)?.isEmpty == false
    }

    func hasAPIKey() -> Bool {
        hasStoredAPIKey
    }

    func setAPIKey(_ value: String) {
        do {
            try secrets.setSecret(value, account: AppConstants.keychainAccount)
            lastError = nil
        } catch {
            lastError = "Storing the API key failed: \(error.localizedDescription)"
        }
        refreshKeyPresence()
    }

    func deleteAPIKey() {
        do {
            try secrets.deleteSecret(account: AppConstants.keychainAccount)
        } catch {
            lastError = "Deleting the API key failed: \(error.localizedDescription)"
        }
        refreshKeyPresence()
    }

    func aiStatus() -> AnalysisService.Status {
        let isReady = settings.analysisAgent.map { selected in
            analysisAgents.contains { $0.kind == selected && $0.isReady }
        } ?? false
        return AnalysisService.status(settings: settings, agentAvailable: isReady)
    }

    func analysisAgentStatus(for kind: AnalysisAgentKind) -> AnalysisAgentStatus? {
        analysisAgents.first { $0.kind == kind && $0.isReady }
    }

    // MARK: Data folder

    var dataDirectory: URL { persistence.directory }

    // MARK: Store recovery

    /// Explicit, user-initiated recovery for a damaged store. On success the
    /// failure state clears and the recovered store reloads; on failure the
    /// failure state stays and a safe message is surfaced. Never presented as
    /// successful unless the original bytes were preserved first.
    public func recoverStore(_ name: StoreName) {
        guard storeFailures[name] != nil else { return }
        switch persistence.recoverStore(name) {
        case .recovered:
            storeFailures[name] = nil
            lastRecoveryMessage = nil
            lastError = nil
            reloadStore(name)
        case .failed(let message):
            lastRecoveryMessage = message
        }
    }

    private func reloadStore(_ name: StoreName) {
        switch name {
        case .events:
            if case .loaded(let value) = persistence.loadEventsHealth() {
                events = value.sorted { $0.timestamp > $1.timestamp }
                eventIndex = EventProjectionIndex(events: events)
            }
        case .corrections:
            if case .loaded(let value) = persistence.loadCorrectionsHealth() { corrections = value }
        case .reports:
            if case .loaded(let value) = persistence.loadReportsHealth() { reports = value }
        case .settings:
            if case .loaded(let value) = persistence.loadSettingsHealth() { settings = value }
        case .manifests:
            if case .loaded(let value) = persistence.loadManifestsHealth() { manifests = value }
        case .sessions:
            // The sessions store holds rich private session content and is
            // read only by the explicit session import path; AppStore keeps
            // no launch-time session state, so there is nothing to reload.
            break
        case .conversations:
            // The conversations store is owned by the conversation service,
            // never loaded at launch, and holds no AppStore state.
            break
        }
    }
}
