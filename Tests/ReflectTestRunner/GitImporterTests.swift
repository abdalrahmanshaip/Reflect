import Foundation
@testable import ReflectLib

struct GitImporterTests {
    static let suiteName = "GitImporterTests"

    func importsCommitsAsUnclearAttributionMetadataOnly() throws {
        let repo = Fixtures.makeTempDirectory("fixture-repo")
        let hash = try Fixtures.initGitRepo(at: repo)

        let events = try GitCommitImporter(repositoryPath: repo).importCommits()
        try expectEqual(events.count, 1)

        let commit = try require(events.first, "expected one commit event")
        try expectEqual(commit.kind, .gitCommit)
        try expectEqual(commit.observedAttribution, .unclear)
        try expectTrue(
            commit.observedAttributionNote.lowercased().contains("authorship"),
            "commit events must explicitly say authorship is not asserted"
        )
        try expectEqual(commit.evidencePath, repo.path)
        try expectTrue(commit.summary.contains("Fixture commit"))
        try expectEqual(
            commit.id,
            EvidenceIdentity.stableID(source: .gitLocal, path: repo.path, line: nil, recordType: "git_commit:\(hash)"),
            "commit id must be derived from the stable commit hash"
        )

        let again = try GitCommitImporter(repositoryPath: repo).importCommits()
        try expectEqual(again.map(\.id), events.map(\.id), "repeat git imports must be stable for dedup")
    }

    static var entries: [TestEntry] {
        let tests = GitImporterTests()
        return [
            TestEntry(suite: suiteName, name: "importsCommitsAsUnclearAttributionMetadataOnly") { try tests.importsCommitsAsUnclearAttributionMetadataOnly() }
        ]
    }
}
