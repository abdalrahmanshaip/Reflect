import Foundation
@testable import ReflectLib

/// Defect 4 regression coverage: the Today analysis privacy line must be
/// truthful across disabled, configured/not-run, run-completed, and
/// restored-attached states — never claiming records were sent before an
/// explicit run, and never claiming nothing left the Mac after one did.
struct AnalysisPrivacyNoteTests {
    static let suiteName = "AnalysisPrivacyNoteTests"

    private let leftThisMac = "Nothing from this day has left this Mac"
    private let sentPhrase = "were sent"

    func disabledAndNoAttachedResultDoesNotClaimRecordsStayedLocal() throws {
        let note = AnalysisPrivacyNote.text(aiEnabled: false, state: .noAttachedResult)
        try expectTrue(note.contains("No saved analysis result is attached"), "the day has no attached result: \(note)")
        try expectFalse(note.contains(leftThisMac), "absence of an attached result cannot prove no earlier run: \(note)")
        try expectTrue(note.contains("turned off"))
        try expectFalse(note.lowercased().contains(sentPhrase), "must never imply records were sent: \(note)")
    }

    func configuredWithoutAttachedResultDoesNotClaimNothingWasSent() throws {
        let note = AnalysisPrivacyNote.text(aiEnabled: true, state: .noAttachedResult)
        try expectTrue(note.contains("No saved analysis result is attached"),
                       "configured-but-idle reports what is known from storage: \(note)")
        try expectFalse(note.contains(leftThisMac),
                        "the unconditional claim is replaced by state-aware wording: \(note)")
        try expectFalse(note.lowercased().contains(sentPhrase),
                        "no attached result does not prove a run occurred: \(note)")
        try expectTrue(note.lowercased().contains("run"), "the wording names the explicit run as the trigger")
    }

    func reopenedDayWithoutAttachedResultDoesNotClaimNothingWasSent() throws {
        // A fresh Today view has no memory of an earlier run that was not
        // attached. The privacy note must describe what is known from storage,
        // not turn an idle in-memory model into a claim about past activity.
        let note = AnalysisPrivacyNote.text(aiEnabled: false, state: .noAttachedResult)
        try expectTrue(note.contains("No saved analysis result is attached"),
                       "the reopened day can only report that no result is attached: \(note)")
        try expectFalse(note.contains(leftThisMac),
                        "an idle model cannot prove no earlier unattached run occurred: \(note)")
        try expectFalse(note.lowercased().contains("nothing has been sent"),
                        "an idle model cannot prove no earlier unattached run occurred: \(note)")
    }

    func runCompletedStatesRecordsWereSent() throws {
        for aiEnabled in [true, false] {
            let note = AnalysisPrivacyNote.text(aiEnabled: aiEnabled, state: .sent)
        try expectFalse(note.contains(leftThisMac), "a completed run falsifies the old claim: \(note)")
        try expectTrue(note.lowercased().contains(sentPhrase),
                       "the line must say records were sent after an explicit run (aiEnabled: \(aiEnabled)): \(note)")
        try expectFalse(note.lowercased().contains("saved result is stored"),
                        "a completed but unattached result must not be described as saved: \(note)")
        }
    }

    func restoredAttachedReportStatesRecordsWereSent() throws {
        for aiEnabled in [true, false] {
            let note = AnalysisPrivacyNote.text(aiEnabled: aiEnabled, state: .sent)
            try expectFalse(note.contains(leftThisMac),
                            "a stored attached result also falsifies the old claim: \(note)")
            try expectTrue(note.lowercased().contains(sentPhrase),
                           "an attached result means records were previously sent (aiEnabled: \(aiEnabled)): \(note)")
        }
    }

    func inFlightAndFailedRunsAreNeitherSilentNorFalse() throws {
        let inFlight = AnalysisPrivacyNote.text(aiEnabled: true, state: .inFlight)
        try expectFalse(inFlight.contains(leftThisMac), "a run in flight falsifies the old claim: \(inFlight)")
        try expectTrue(inFlight.lowercased().contains("sent"), "in flight names the sending: \(inFlight)")

        let failed = AnalysisPrivacyNote.text(aiEnabled: true, state: .attemptFailed)
        try expectFalse(failed.contains(leftThisMac),
                        "after a failed attempt it is unknown whether anything left the Mac: \(failed)")
        try expectFalse(failed.lowercased().contains(sentPhrase),
                        "a failed attempt must not claim records were (successfully) sent: \(failed)")
        try expectTrue(failed.lowercased().contains("unknown"),
                       "failure honestly reports the unknown outcome: \(failed)")
    }

    static var entries: [TestEntry] {
        let tests = AnalysisPrivacyNoteTests()
        return [
            TestEntry(suite: suiteName, name: "disabledAndNoAttachedResultDoesNotClaimRecordsStayedLocal") { try tests.disabledAndNoAttachedResultDoesNotClaimRecordsStayedLocal() },
            TestEntry(suite: suiteName, name: "configuredWithoutAttachedResultDoesNotClaimNothingWasSent") { try tests.configuredWithoutAttachedResultDoesNotClaimNothingWasSent() },
            TestEntry(suite: suiteName, name: "reopenedDayWithoutAttachedResultDoesNotClaimNothingWasSent") { try tests.reopenedDayWithoutAttachedResultDoesNotClaimNothingWasSent() },
            TestEntry(suite: suiteName, name: "runCompletedStatesRecordsWereSent") { try tests.runCompletedStatesRecordsWereSent() },
            TestEntry(suite: suiteName, name: "restoredAttachedReportStatesRecordsWereSent") { try tests.restoredAttachedReportStatesRecordsWereSent() },
            TestEntry(suite: suiteName, name: "inFlightAndFailedRunsAreNeitherSilentNorFalse") { try tests.inFlightAndFailedRunsAreNeitherSilentNorFalse() }
        ]
    }
}
