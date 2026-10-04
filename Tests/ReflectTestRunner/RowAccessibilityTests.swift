import Foundation
@testable import ReflectLib

/// Defect 5 regression coverage: This Week day rows and Today evidence
/// inspector record rows are native keyboard-activatable controls with clear
/// VoiceOver labels describing the row and its action.
struct RowAccessibilityTests {
    static let suiteName = "RowAccessibilityTests"

    func weekDayRowLabelsDescribeDayAndAction() throws {
        let label = RowAccessibility.weekDayRowLabel(weekday: "Monday", dayLabel: "Jan 5", isToday: false, count: 3)
        try expectFalse(label.trimmingCharacters(in: .whitespaces).isEmpty, "day rows need a VoiceOver label")
        try expectTrue(label.contains("Monday") && label.contains("Jan 5"), "label names the day: \(label)")
        try expectTrue(label.contains("3 records"), "label reports the record count: \(label)")
        try expectTrue(label.contains("Opens this day in Today"), "label states the activation action: \(label)")
        try expectFalse(label.lowercased().contains(", today"), "a non-today row must not claim today: \(label)")

        let todayLabel = RowAccessibility.weekDayRowLabel(weekday: "Tuesday", dayLabel: "Jan 6", isToday: true, count: 0)
        try expectTrue(todayLabel.contains("no records"), "an empty day says no records rather than 0 records: \(todayLabel)")
        try expectFalse(todayLabel.contains("0 records"), "no fabricated count: \(todayLabel)")
        try expectTrue(todayLabel.contains(", today"), "the current day is announced: \(todayLabel)")
        try expectTrue(todayLabel.contains("Opens this day in Today"), "activation action present: \(todayLabel)")
    }

    func recordRowLabelsDescribeRecordAttributionAndAction() throws {
        let label = RowAccessibility.recordRowLabel(time: "09:15", summary: "Synthetic session record", attribution: "Agent", isCorrected: false)
        try expectFalse(label.trimmingCharacters(in: .whitespaces).isEmpty, "record rows need a VoiceOver label")
        try expectTrue(label.contains("09:15") && label.contains("Synthetic session record"),
                       "label names the record's time and summary: \(label)")
        try expectTrue(label.contains("Agent"), "label names the attribution badge value: \(label)")
        try expectFalse(label.lowercased().contains("your correction"),
                        "an uncorrected record must not claim a correction: \(label)")
        try expectTrue(label.contains("Opens the record detail"), "label states the activation action: \(label)")

        let corrected = RowAccessibility.recordRowLabel(time: "10:00", summary: "Another synthetic record", attribution: "You", isCorrected: true)
        try expectTrue(corrected.lowercased().contains("your correction"),
                       "a corrected record announces the correction: \(corrected)")
        try expectTrue(corrected.contains("You"), "corrected label keeps the attribution value: \(corrected)")
        try expectFalse(corrected.lowercased().contains("you wrote"),
                        "attribution badge values never become authorship claims: \(corrected)")
    }

    static var entries: [TestEntry] {
        let tests = RowAccessibilityTests()
        return [
            TestEntry(suite: suiteName, name: "weekDayRowLabelsDescribeDayAndAction") { try tests.weekDayRowLabelsDescribeDayAndAction() },
            TestEntry(suite: suiteName, name: "recordRowLabelsDescribeRecordAttributionAndAction") { try tests.recordRowLabelsDescribeRecordAttributionAndAction() }
        ]
    }
}
