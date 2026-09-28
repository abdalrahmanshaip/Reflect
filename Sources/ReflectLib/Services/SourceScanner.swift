import Foundation

/// Availability metadata is gathered by listing directories and stat-ing files only.
/// This scanner never reads file contents.
struct SourceScanner {
    let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    func availability(for kind: SourceKind, settings: AppSettings) -> SourceAvailability {
        switch kind {
        case .gitLocal:
            return gitAvailability(path: settings.gitRepositoryPath)
        case .cursor, .vscode:
            return scan(kind: kind, verified: false)
        default:
            return scan(kind: kind, verified: true)
        }
    }

    func candidateFiles(for kind: SourceKind) -> [URL] {
        guard kind != .gitLocal else { return [] }
        var files: [URL] = []
        for relativeRoot in kind.defaultHomeRelativeRoots {
            let root = home.appendingPathComponent(relativeRoot, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            files.append(contentsOf: candidateFiles(in: root, kind: kind))
        }
        return files.sorted { $0.path < $1.path }
    }

    private func scan(kind: SourceKind, verified: Bool) -> SourceAvailability {
        let fileManager = FileManager.default
        var count = 0
        var lastModified: Date?
        var firstRoot: String?
        var rootExists = false

        for relativeRoot in kind.defaultHomeRelativeRoots {
            let root = home.appendingPathComponent(relativeRoot, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            rootExists = true
            if firstRoot == nil { firstRoot = root.path }
            for url in candidateFiles(in: root, kind: kind) {
                count += 1
                if count <= 400, let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                    if lastModified == nil || modified > lastModified! {
                        lastModified = modified
                    }
                }
            }
        }

        guard rootExists, count > 0 else {
            return SourceAvailability(status: .missing, fileCount: 0, rootPath: firstRoot, lastModified: nil, note: nil)
        }

        let status: SourceAvailability.Status = verified ? .detected : .detectedUnverified
        let note: String? = verified
            ? nil
            : "Structured store (not line-oriented JSONL). Reading it safely needs its own verified adapter."
        return SourceAvailability(status: status, fileCount: count, rootPath: firstRoot, lastModified: lastModified, note: note)
    }

    private func candidateFiles(in root: URL, kind: SourceKind) -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator {
            if Self.matchesFileName(url.lastPathComponent, kind: kind) {
                files.append(url)
            }
        }
        return files
    }

    private func gitAvailability(path: String?) -> SourceAvailability {
        guard let path, !path.isEmpty else {
            return SourceAvailability(
                status: .missing,
                fileCount: 0,
                rootPath: nil,
                lastModified: nil,
                note: "No repository selected. Choose one in the Sources tab."
            )
        }
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return SourceAvailability(
                status: .missing,
                fileCount: 0,
                rootPath: path,
                lastModified: nil,
                note: "Selected path no longer exists."
            )
        }
        return SourceAvailability(
            status: .manual,
            fileCount: 1,
            rootPath: path,
            lastModified: nil,
            note: "Commits are read only when you start an import."
        )
    }

    static func matchesFileName(_ name: String, kind: SourceKind) -> Bool {
        switch kind {
        case .codex:
            return name.hasPrefix("rollout-") && name.hasSuffix(".jsonl")
        case .claudeCode:
            return name.hasSuffix(".jsonl")
        case .copilotCLI:
            return name == "events.jsonl"
        case .cursor, .vscode:
            return name == "state.vscdb"
        case .gitLocal:
            return false
        }
    }
}
