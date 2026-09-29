import Foundation
@testable import ReflectLib

struct ReportEditTrackingTests {
    static let suiteName = "ReportEditTrackingTests"

    func restoringSavedNarrativeIsNotAnEdit() throws {
        try expectFalse(ReportEditTracking.narrativeChanged(current: "Saved draft", saved: "Saved draft"))
    }

    func changingNarrativeIsAnEdit() throws {
        try expectTrue(ReportEditTracking.narrativeChanged(current: "Edited draft", saved: "Saved draft"))
    }

    static var entries: [TestEntry] {
        let tests = ReportEditTrackingTests()
        return [
            TestEntry(suite: suiteName, name: "restoringSavedNarrativeIsNotAnEdit") { try tests.restoringSavedNarrativeIsNotAnEdit() },
            TestEntry(suite: suiteName, name: "changingNarrativeIsAnEdit") { try tests.changingNarrativeIsAnEdit() }
        ]
    }
}
