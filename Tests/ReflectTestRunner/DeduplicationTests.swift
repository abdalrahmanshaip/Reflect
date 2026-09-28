import Foundation
@testable import ReflectLib

struct DeduplicationTests {
    static let suiteName = "DeduplicationTests"

    private func runEngine(_ file: URL) -> [EvidenceEvent] {
        JSONLImportEngine(
            importer: CodexImporter(),
            fileURL: file,
            sourceName: "Codex CLI",
            maxPreviewCharacters: 160
        ).run()
    }

    func repeatImportDoesNotDuplicateEvents() throws {
        let dir = Fixtures.makeTempDirectory("dedup")
        let file = dir.appendingPathComponent("rollout-dedup.jsonl")
        Fixtures.write(Fixtures.codexFixtureText, to: file)

        let first = runEngine(file)
        let second = runEngine(file)
        try expectEqual(first.map(\.id), second.map(\.id), "ids must be stable across repeated imports")

        let r1 = EventDeduplicator.merge(existing: [], incoming: first)
        try expectEqual(r1.added, first.count)

        let r2 = EventDeduplicator.merge(existing: r1.merged, incoming: second)
        try expectEqual(r2.added, 0, "re-importing the same file must add nothing")
        try expectEqual(r2.merged.count, r1.merged.count)
    }

    func differentLinesProduceDifferentEvidenceIDs() throws {
        let dir = Fixtures.makeTempDirectory("dedup-lines")
        let file = dir.appendingPathComponent("rollout-lines.jsonl")
        Fixtures.write(Fixtures.codexFixtureText, to: file)
        let events = runEngine(file)
        try expectEqual(Set(events.map(\.id)).count, events.count)
    }

    func sameContentInAnotherFileIsDistinctEvidence() throws {
        let dir = Fixtures.makeTempDirectory("dedup-paths")
        let fileA = dir.appendingPathComponent("rollout-a.jsonl")
        let fileB = dir.appendingPathComponent("rollout-b.jsonl")
        Fixtures.write(Fixtures.codexFixtureText, to: fileA)
        Fixtures.write(Fixtures.codexFixtureText, to: fileB)

        let eventsA = runEngine(fileA)
        let eventsB = runEngine(fileB)
        let merge = EventDeduplicator.merge(existing: eventsA, incoming: eventsB)
        try expectEqual(merge.added, eventsB.count, "same content in a different file is separate evidence")
        try expectEqual(merge.merged.count, eventsA.count + eventsB.count)
    }

    static var entries: [TestEntry] {
        let tests = DeduplicationTests()
        return [
            TestEntry(suite: suiteName, name: "repeatImportDoesNotDuplicateEvents") { try tests.repeatImportDoesNotDuplicateEvents() },
            TestEntry(suite: suiteName, name: "differentLinesProduceDifferentEvidenceIDs") { try tests.differentLinesProduceDifferentEvidenceIDs() },
            TestEntry(suite: suiteName, name: "sameContentInAnotherFileIsDistinctEvidence") { try tests.sameContentInAnotherFileIsDistinctEvidence() }
        ]
    }
}
