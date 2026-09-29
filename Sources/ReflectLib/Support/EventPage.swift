import Foundation

/// Keeps large evidence days from creating an unbounded SwiftUI control tree.
enum EventPage {
    static func pageCount(total: Int, pageSize: Int) -> Int {
        guard total > 0, pageSize > 0 else { return 0 }
        return 1 + (total - 1) / pageSize
    }

    static func range(total: Int, page: Int, pageSize: Int) -> Range<Int> {
        guard total > 0, pageSize > 0 else { return 0..<0 }
        let lastPage = pageCount(total: total, pageSize: pageSize) - 1
        let safePage = min(max(page, 0), lastPage)
        let start = safePage * pageSize
        return start..<min(start + pageSize, total)
    }

    static func items<Element>(_ items: [Element], page: Int, pageSize: Int) -> [Element] {
        Array(items[range(total: items.count, page: page, pageSize: pageSize)])
    }
}
