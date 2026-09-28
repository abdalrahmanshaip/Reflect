import Foundation
@testable import ReflectLib

struct MissingSourceTests {
    static let suiteName = "MissingSourceTests"

    func scannerReportsMissingWhenRootAbsent() throws {
        let home = Fixtures.makeTempDirectory("empty-home")
        let availability = SourceScanner(home: home).availability(for: .codex, settings: AppSettings())
        try expectEqual(availability.status, .missing)
        try expectEqual(availability.fileCount, 0)
    }

    func scannerCountsCodexFilesWhenPresent() throws {
        let home = Fixtures.makeTempDirectory("codex-home")
        Fixtures.codexSessionTree(in: home)
        let availability = SourceScanner(home: home).availability(for: .codex, settings: AppSettings())
        try expectEqual(availability.status, .detected)
        try expectEqual(availability.fileCount, 1)
    }

    func scannerReportsDetectedUnverifiedForCursor() throws {
        let home = Fixtures.makeTempDirectory("cursor-home")
        let ws = home.appendingPathComponent("Library/Application Support/Cursor/User/workspaceStorage/ws1", isDirectory: true)
        try! FileManager.default.createDirectory(at: ws, withIntermediateDirectories: true)
        Fixtures.write("placeholder bytes", to: ws.appendingPathComponent("state.vscdb"))

        let availability = SourceScanner(home: home).availability(for: .cursor, settings: AppSettings())
        try expectEqual(availability.status, .detectedUnverified)
        try expectEqual(availability.fileCount, 1)
    }

    func importOfMissingSourceYieldsNoteAndNoEvents() throws {
        let home = Fixtures.makeTempDirectory("empty-home-2")
        let outcome = ImportOrchestrator.importSource(kind: .codex, home: home, settings: AppSettings())
        try expectTrue(outcome.events.isEmpty)
        try expectEqual(outcome.filesScanned, 0)
        try expectTrue(outcome.note != nil, "missing source must be reported honestly")
    }

    func unverifiedSourceIsNeverImportedOrClaimed() throws {
        let home = Fixtures.makeTempDirectory("cursor-home-2")
        let ws = home.appendingPathComponent("Library/Application Support/Cursor/User/workspaceStorage/ws1", isDirectory: true)
        try! FileManager.default.createDirectory(at: ws, withIntermediateDirectories: true)
        Fixtures.write("placeholder bytes", to: ws.appendingPathComponent("state.vscdb"))

        let outcome = ImportOrchestrator.importSource(kind: .cursor, home: home, settings: AppSettings())
        try expectTrue(outcome.events.isEmpty)
        try expectTrue(outcome.note?.contains("not yet verified") == true, "status must say the format is not verified")
    }

    func disabledSourceIsSkipped() throws {
        var settings = AppSettings()
        settings.enabledSources = []
        let outcome = ImportOrchestrator.importSource(
            kind: .codex,
            home: Fixtures.makeTempDirectory("disabled-home"),
            settings: settings
        )
        try expectTrue(outcome.events.isEmpty)
        try expectTrue(outcome.note?.lowercased().contains("disabled") == true)
    }

    func gitImportWithoutSelectedRepositoryIsHonest() throws {
        let outcome = ImportOrchestrator.importSource(
            kind: .gitLocal,
            home: Fixtures.makeTempDirectory("git-home"),
            settings: AppSettings()
        )
        try expectTrue(outcome.events.isEmpty)
        try expectTrue(outcome.note != nil)
    }

    static var entries: [TestEntry] {
        let tests = MissingSourceTests()
        return [
            TestEntry(suite: suiteName, name: "scannerReportsMissingWhenRootAbsent") { try tests.scannerReportsMissingWhenRootAbsent() },
            TestEntry(suite: suiteName, name: "scannerCountsCodexFilesWhenPresent") { try tests.scannerCountsCodexFilesWhenPresent() },
            TestEntry(suite: suiteName, name: "scannerReportsDetectedUnverifiedForCursor") { try tests.scannerReportsDetectedUnverifiedForCursor() },
            TestEntry(suite: suiteName, name: "importOfMissingSourceYieldsNoteAndNoEvents") { try tests.importOfMissingSourceYieldsNoteAndNoEvents() },
            TestEntry(suite: suiteName, name: "unverifiedSourceIsNeverImportedOrClaimed") { try tests.unverifiedSourceIsNeverImportedOrClaimed() },
            TestEntry(suite: suiteName, name: "disabledSourceIsSkipped") { try tests.disabledSourceIsSkipped() },
            TestEntry(suite: suiteName, name: "gitImportWithoutSelectedRepositoryIsHonest") { try tests.gitImportWithoutSelectedRepositoryIsHonest() }
        ]
    }
}
