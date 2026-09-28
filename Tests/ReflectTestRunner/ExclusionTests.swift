import Foundation
@testable import ReflectLib

struct ExclusionTests {
    static let suiteName = "ExclusionTests"

    func policyMatchesSubstringCaseInsensitively() throws {
        let policy = ExclusionPolicy(["PrivateProject"])
        try expectTrue(policy.isExcluded(path: "/Users/dev/privateproject/file.jsonl"))
        try expectFalse(policy.isExcluded(path: "/Users/dev/other/file.jsonl"))
    }

    func blankTokensAreIgnored() throws {
        let policy = ExclusionPolicy(["  ", "", "\n"])
        try expectFalse(policy.isExcluded(path: "/Users/dev/anything/file.jsonl"))
    }

    func orchestratorSkipsExcludedFiles() throws {
        let home = Fixtures.makeTempDirectory("excl-home")
        Fixtures.codexSessionTree(in: home)
        Fixtures.claudeProjectTree(in: home)

        var settings = AppSettings()
        settings.exclusions = ["excl-home"]
        let outcome = ImportOrchestrator.importSource(kind: .codex, home: home, settings: settings)
        try expectTrue(outcome.events.isEmpty, "excluded paths must not be imported")
    }

    func orchestratorKeepsNonExcludedFiles() throws {
        let home = Fixtures.makeTempDirectory("keep-home")
        Fixtures.codexSessionTree(in: home)

        var settings = AppSettings()
        settings.exclusions = ["totally-unrelated-token"]
        let outcome = ImportOrchestrator.importSource(kind: .codex, home: home, settings: settings)
        try expectFalse(outcome.events.isEmpty)
    }

    static var entries: [TestEntry] {
        let tests = ExclusionTests()
        return [
            TestEntry(suite: suiteName, name: "policyMatchesSubstringCaseInsensitively") { try tests.policyMatchesSubstringCaseInsensitively() },
            TestEntry(suite: suiteName, name: "blankTokensAreIgnored") { try tests.blankTokensAreIgnored() },
            TestEntry(suite: suiteName, name: "orchestratorSkipsExcludedFiles") { try tests.orchestratorSkipsExcludedFiles() },
            TestEntry(suite: suiteName, name: "orchestratorKeepsNonExcludedFiles") { try tests.orchestratorKeepsNonExcludedFiles() }
        ]
    }
}
