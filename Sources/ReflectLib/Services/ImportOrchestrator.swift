import Foundation

/// The result of one source adapter run: counts and safe notes only. Payload
/// text never enters an outcome.
public struct ImportOutcome {
    public let kind: SourceKind
    public var events: [EvidenceEvent]
    public var filesScanned: Int
    public var note: String?

    public init(kind: SourceKind, events: [EvidenceEvent], filesScanned: Int, note: String?) {
        self.kind = kind
        self.events = events
        self.filesScanned = filesScanned
        self.note = note
    }
}

/// Runs one source's import work away from the main actor. The default is the
/// real local, read-only orchestrator; tests inject a recording fake to
/// observe the scheduling boundary without reading anything from disk.
public typealias ImportSourceExecutor = @Sendable (SourceKind, URL, AppSettings) async -> ImportOutcome

/// Runs an import for one source. Only called from an explicit user action;
/// nothing here runs automatically or touches the network.
enum ImportOrchestrator {
    static func importSource(kind: SourceKind, home: URL, settings: AppSettings, now: Date = Date()) -> ImportOutcome {
        guard settings.enabledSources.contains(kind) else {
            return ImportOutcome(kind: kind, events: [], filesScanned: 0, note: "Source is disabled in Settings.")
        }

        let policy = ExclusionPolicy(settings.exclusions)

        switch kind {
        case .codex:
            return importLineOriented(CodexImporter(), home: home, policy: policy, settings: settings, now: now)
        case .claudeCode:
            return importLineOriented(ClaudeCodeImporter(), home: home, policy: policy, settings: settings, now: now)
        case .copilotCLI:
            return importLineOriented(CopilotCLIImporter(), home: home, policy: policy, settings: settings, now: now)
        case .cursor, .vscode:
            return ImportOutcome(
                kind: kind,
                events: [],
                filesScanned: 0,
                note: "Detected; format not yet verified. Import is intentionally not implemented for this structured store."
            )
        case .gitLocal:
            return importGit(policy: policy, settings: settings, now: now)
        }
    }

    private static func importLineOriented(
        _ importer: LineOrientedImporter,
        home: URL,
        policy: ExclusionPolicy,
        settings: AppSettings,
        now: Date
    ) -> ImportOutcome {
        let scanner = SourceScanner(home: home)
        let files = scanner.candidateFiles(for: importer.sourceKind).filter { !policy.isExcluded(path: $0.path) }

        guard !files.isEmpty else {
            return ImportOutcome(
                kind: importer.sourceKind,
                events: [],
                filesScanned: 0,
                note: "Source not detected at the expected location under the home directory."
            )
        }

        var events: [EvidenceEvent] = []
        for file in files {
            let engine = JSONLImportEngine(
                importer: importer,
                fileURL: file,
                sourceName: importer.sourceName,
                maxPreviewCharacters: settings.maxPreviewCharacters
            )
            events.append(contentsOf: engine.run(now: now))
        }

        return ImportOutcome(
            kind: importer.sourceKind,
            events: events,
            filesScanned: files.count,
            note: nil
        )
    }

    private static func importGit(policy: ExclusionPolicy, settings: AppSettings, now: Date) -> ImportOutcome {
        guard let path = settings.gitRepositoryPath, !path.isEmpty else {
            return ImportOutcome(
                kind: .gitLocal,
                events: [],
                filesScanned: 0,
                note: "No repository selected. Choose one in the Sources tab."
            )
        }
        do {
            let importer = GitCommitImporter(repositoryPath: URL(fileURLWithPath: path))
            let events = try importer.importCommits().filter { !policy.isExcluded(path: $0.evidencePath) }
            return ImportOutcome(kind: .gitLocal, events: events, filesScanned: 1, note: nil)
        } catch {
            return ImportOutcome(
                kind: .gitLocal,
                events: [],
                filesScanned: 0,
                note: "Git import failed. Check the selected repository and try again."
            )
        }
    }
}
