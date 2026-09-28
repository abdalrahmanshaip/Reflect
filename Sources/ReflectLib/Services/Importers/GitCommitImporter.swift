import Foundation

enum ProcessRunner {
    struct Result {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    static func run(executablePath: String, arguments: [String], currentDirectory: URL?) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return Result(stdout: out, stderr: err, exitCode: process.terminationStatus)
    }
}

/// Reads commit metadata from a git repository the user picked manually.
/// Read-only. Commit author fields are stored as metadata and attribution stays `unclear`:
/// commits are never equated with authorship.
struct GitCommitImporter {
    let repositoryPath: URL

    func importCommits(limit: Int = AppConstants.maxGitCommits) throws -> [EvidenceEvent] {
        let separator = "\u{1f}"
        let recordEnd = "\u{1e}"
        let format = "%H\(separator)%aI\(separator)%an\(separator)%ae\(separator)%s\(recordEnd)"
        let result = try ProcessRunner.run(
            executablePath: "/usr/bin/git",
            arguments: [
                "-C", repositoryPath.path,
                "log", "--all", "--no-color",
                "--max-count=\(limit)",
                "--date=iso8601-strict",
                "--pretty=format:\(format)"
            ],
            currentDirectory: repositoryPath
        )

        guard result.exitCode == 0 else {
            throw ImportError.gitFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        var events: [EvidenceEvent] = []
        let now = Date()
        for record in result.stdout.split(separator: recordEnd) {
            let fields = record.split(separator: Character(separator), omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 5 else { continue }
            let hash = fields[0]
            guard hash.count >= 7 else { continue }
            let isoDate = fields[1]
            let authorName = fields[2]
            let authorEmail = fields[3]
            let subject = fields[4]

            let parsedDate = TimestampParser.parse(isoDate)
            let timestamp = parsedDate ?? now
            let shortSubject = JSONParsing.cappedPreview(subject, limit: 120)

            events.append(EvidenceEvent(
                id: EvidenceIdentity.stableID(
                    source: .gitLocal,
                    path: repositoryPath.path,
                    line: nil,
                    recordType: "git_commit:\(hash)"
                ),
                sourceKind: .gitLocal,
                sourceName: SourceKind.gitLocal.displayName,
                timestamp: timestamp,
                timestampApproximate: parsedDate == nil,
                kind: .gitCommit,
                summary: "Commit \(hash.prefix(7)): \(shortSubject)",
                detail: "Git records author as \(authorName) <\(authorEmail)>. Repository metadata only; authorship is not asserted.",
                evidencePath: repositoryPath.path,
                evidenceLine: nil,
                observedAttribution: .unclear,
                observedAttributionNote: "Commit metadata only; authorship is not asserted.",
                importedAt: now
            ))
        }
        return events
    }

    enum ImportError: LocalizedError {
        case gitFailed(String)

        var errorDescription: String? {
            switch self {
            case .gitFailed(let message):
                return message.isEmpty ? "git command failed." : message
            }
        }
    }
}
