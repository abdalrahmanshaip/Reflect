import Foundation
@testable import ReflectLib

struct TimestampParserTests {
    static let suiteName = "TimestampParserTests"

    func parsesISO8601UTC() throws {
        try expectEqual(TimestampParser.parse("2026-01-05T09:00:00Z"), Date(timeIntervalSince1970: 1_767_603_600))
    }

    func parsesFractionalSeconds() throws {
        try expectEqual(TimestampParser.parse("2026-01-05T09:00:00.250Z"), Date(timeIntervalSince1970: 1_767_603_600.25))
    }

    func parsesOffsetTimestamp() throws {
        try expectEqual(TimestampParser.parse("2026-01-05T10:00:00+01:00"), Date(timeIntervalSince1970: 1_767_603_600))
    }

    func parsesEpochSeconds() throws {
        try expectEqual(TimestampParser.parse(1_767_603_600), Date(timeIntervalSince1970: 1_767_603_600))
    }

    func parsesEpochMillis() throws {
        try expectEqual(TimestampParser.parse(1_767_603_600_500), Date(timeIntervalSince1970: 1_767_603_600.5))
    }

    func rejectsGarbageAndNil() throws {
        try expectNil(TimestampParser.parse("not-a-date"))
        try expectNil(TimestampParser.parse(nil))
        try expectNil(TimestampParser.parse(3.14))
    }

    static var entries: [TestEntry] {
        let tests = TimestampParserTests()
        return [
            TestEntry(suite: suiteName, name: "parsesISO8601UTC") { try tests.parsesISO8601UTC() },
            TestEntry(suite: suiteName, name: "parsesFractionalSeconds") { try tests.parsesFractionalSeconds() },
            TestEntry(suite: suiteName, name: "parsesOffsetTimestamp") { try tests.parsesOffsetTimestamp() },
            TestEntry(suite: suiteName, name: "parsesEpochSeconds") { try tests.parsesEpochSeconds() },
            TestEntry(suite: suiteName, name: "parsesEpochMillis") { try tests.parsesEpochMillis() },
            TestEntry(suite: suiteName, name: "rejectsGarbageAndNil") { try tests.rejectsGarbageAndNil() }
        ]
    }
}
