import Foundation

/// Small atomic JSON file persistence layer. Everything lives in the user's
/// Application Support/Reflect folder as human-readable JSON files.
struct JSONFileStore<T: Codable> {
    let url: URL

    func load() throws -> T? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    func save(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let temporaryURL = directory.appendingPathComponent("." + url.lastPathComponent + ".tmp-\(UUID().uuidString)")
        try data.write(to: temporaryURL, options: .atomic)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
    }
}

/// Owns the file layout under Application Support/Reflect.
struct PersistenceController {
    let directory: URL

    private var eventsStore: JSONFileStore<[EvidenceEvent]> {
        JSONFileStore(url: directory.appendingPathComponent("events.json"))
    }
    private var correctionsStore: JSONFileStore<[AttributionCorrection]> {
        JSONFileStore(url: directory.appendingPathComponent("corrections.json"))
    }
    private var reportsStore: JSONFileStore<[DailyReport]> {
        JSONFileStore(url: directory.appendingPathComponent("reports.json"))
    }
    private var settingsStore: JSONFileStore<AppSettings> {
        JSONFileStore(url: directory.appendingPathComponent("settings.json"))
    }
    private var manifestsStore: JSONFileStore<[SourceKind: SourceManifest]> {
        JSONFileStore(url: directory.appendingPathComponent("manifests.json"))
    }

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(AppConstants.appSupportFolderName, isDirectory: true)
    }

    // MARK: Events

    func saveEvents(_ events: [EvidenceEvent]) throws { try eventsStore.save(events) }
    func loadEvents() throws -> [EvidenceEvent] { try eventsStore.load() ?? [] }

    // MARK: Corrections (stored independently of events)

    func saveCorrections(_ corrections: [AttributionCorrection]) throws { try correctionsStore.save(corrections) }
    func loadCorrections() throws -> [AttributionCorrection] { try correctionsStore.load() ?? [] }

    // MARK: Reports

    func saveReports(_ reports: [DailyReport]) throws { try reportsStore.save(reports) }
    func loadReports() throws -> [DailyReport] { try reportsStore.load() ?? [] }

    // MARK: Settings

    func saveSettings(_ settings: AppSettings) throws { try settingsStore.save(settings) }
    func loadSettings() throws -> AppSettings { try settingsStore.load() ?? AppSettings.default() }

    // MARK: Manifests

    func saveManifests(_ manifests: [SourceKind: SourceManifest]) throws { try manifestsStore.save(manifests) }
    func loadManifests() throws -> [SourceKind: SourceManifest] { try manifestsStore.load() ?? [:] }
}
