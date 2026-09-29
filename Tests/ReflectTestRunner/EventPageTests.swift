import Foundation
@testable import ReflectLib

struct EventPageTests {
    static let suiteName = "EventPageTests"

    func largeDayIsSplitIntoBoundedPages() throws {
        let events = Array(0..<2_009)
        let pageSize = 25
        let pageCount = EventPage.pageCount(total: events.count, pageSize: pageSize)
        try expectEqual(pageCount, 81)
        try expectEqual(EventPage.items(events, page: 0, pageSize: pageSize), Array(0..<25))
        try expectEqual(EventPage.items(events, page: 80, pageSize: pageSize), Array(2_000..<2_009))
        try expectTrue((0..<pageCount).allSatisfy { EventPage.range(total: events.count, page: $0, pageSize: pageSize).count <= pageSize })
    }

    func pageIndexIsClampedToAvailableData() throws {
        try expectEqual(EventPage.items(["a", "b", "c"], page: -1, pageSize: 2), ["a", "b"])
        try expectEqual(EventPage.items(["a", "b", "c"], page: 99, pageSize: 2), ["c"])
    }

    func emptyDataProducesNoPage() throws {
        try expectEqual(EventPage.pageCount(total: 0, pageSize: 25), 0)
        try expectEqual(EventPage.range(total: 0, page: 0, pageSize: 25), 0..<0)
        try expectTrue(EventPage.items([Int](), page: 0, pageSize: 25).isEmpty)
    }

    static var entries: [TestEntry] {
        let tests = EventPageTests()
        return [
            TestEntry(suite: suiteName, name: "largeDayIsSplitIntoBoundedPages") { try tests.largeDayIsSplitIntoBoundedPages() },
            TestEntry(suite: suiteName, name: "pageIndexIsClampedToAvailableData") { try tests.pageIndexIsClampedToAvailableData() },
            TestEntry(suite: suiteName, name: "emptyDataProducesNoPage") { try tests.emptyDataProducesNoPage() }
        ]
    }
}
