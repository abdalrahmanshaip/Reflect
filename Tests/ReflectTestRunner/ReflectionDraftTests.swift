import Foundation
@testable import ReflectLib

struct ReflectionDraftTests {
    static let suiteName = "ReflectionDraftTests"
    private let dayKey = "2026-01-05"

    /// Mutable fake store for the injected save closure (closures cannot capture
    /// inout parameters).
    private final class ReportBox {
        var reports: [DailyReport] = []
        var failuresLeft = 0
    }

    private func questions() -> [SuggestedQuestion] {
        [
            SuggestedQuestion(id: "\(dayKey)-q1", text: "Synthetic question one?", basis: "Based on 4 record(s)."),
            SuggestedQuestion(id: "\(dayKey)-q2", text: "Synthetic question two?", basis: "Based on observed roles.")
        ]
    }

    private func report(narrative: String = "Generated draft prose — must never become a draft answer.") -> DailyReport {
        DailyReport(
            day: dayKey,
            narrative: narrative,
            narrativeGeneratedAt: Fixtures.referenceDate,
            answers: [:],
            analysisResult: nil,
            analysisGeneratedAt: nil,
            updatedAt: Fixtures.referenceDate
        )
    }

    @MainActor
    private func makeModel(
        box: ReportBox,
        report: DailyReport,
        questions: [SuggestedQuestion],
        evidenceSignature: String = ""
    ) -> ReflectionDraftModel {
        ReflectionDraftModel(
            dayKey: dayKey,
            report: report,
            questions: questions,
            evidenceSignature: evidenceSignature
        ) { updated in
            if box.failuresLeft > 0 {
                box.failuresLeft -= 1
                return false
            }
            box.reports.removeAll { $0.day == updated.day }
            box.reports.append(updated)
            return true
        }
    }

    // Generated prose is never prefilled into the user's editor.
    @MainActor
    func generatedNarrativeIsNeverPrefilledIntoComposer() throws {
        let box = ReportBox()
        let model = makeModel(box: box, report: report(), questions: questions())
        try expectTrue(model.text(for: "\(dayKey)-q1").isEmpty, "the editor starts empty")
        for (id, text) in model.answers {
            try expectFalse(text.contains("Generated draft"), "answer \(id) must never contain generated prose")
        }
        try expectTrue(box.reports.isEmpty, "merely opening the composer must not save")
    }

    // Editing, switching days immediately, and returning restores the exact text.
    @MainActor
    func draftsSurviveImmediateDaySwitchAndReturn() throws {
        let box = ReportBox()
        let exactText = "Synthetic draft written right before switching days — kept verbatim."
        let first = makeModel(box: box, report: report(), questions: questions())
        first.updateText(exactText, for: "\(dayKey)-q1")
        try expectEqual(first.saveState, .saving, "a draft edit shows the saving state")
        first.flushPendingSave()  // immediate switch: the debounce never fires
        try expectEqual(box.reports.count, 1, "flush must persist the pending draft")

        // Returning to the day reloads the exact text.
        let returning = makeModel(box: box, report: box.reports[0], questions: questions())
        try expectEqual(returning.text(for: "\(dayKey)-q1"), exactText)
    }

    // Trying another question and returning keeps both answers under stable IDs.
    @MainActor
    func tryingAnotherQuestionPreservesBothAnswers() throws {
        let box = ReportBox()
        let model = makeModel(box: box, report: report(), questions: questions())
        try expectEqual(model.selectedQuestion?.id, "\(dayKey)-q1")

        model.updateText("Synthetic answer for the first question.", for: "\(dayKey)-q1")
        model.selectNextQuestion()
        try expectEqual(model.selectedQuestion?.id, "\(dayKey)-q2", "try-another switches the visible question")
        model.updateText("Synthetic answer for the second question.", for: "\(dayKey)-q2")
        model.flushPendingSave()

        let reloaded = makeModel(box: box, report: box.reports[0], questions: questions())
        try expectEqual(reloaded.text(for: "\(dayKey)-q1"), "Synthetic answer for the first question.")
        try expectEqual(reloaded.text(for: "\(dayKey)-q2"), "Synthetic answer for the second question.")
        try expectEqual(Set(reloaded.answers.keys), Set(["\(dayKey)-q1", "\(dayKey)-q2"]), "both stable question IDs keep their answers")
    }

    // Blank text is not a committable reflection; a saved nonblank answer marks the day.
    @MainActor
    func blankSavesAreRejectedAndNonblankMarksReflected() throws {
        try expectTrue(ReflectionDraftModel.isBlankAnswer("   \n\t "), "whitespace-only text is blank")
        try expectFalse(ReflectionDraftModel.isBlankAnswer(" Real reflection "))

        let box = ReportBox()
        let model = makeModel(box: box, report: report(), questions: questions())
        model.updateText("   ", for: "\(dayKey)-q1")
        model.flushPendingSave()
        try expectTrue(box.reports.isEmpty || box.reports[0].answers.isEmpty, "whitespace-only drafts must not persist as answers")

        model.updateText("Synthetic authored reflection.", for: "\(dayKey)-q1")
        model.flushPendingSave()
        let saved = try require(box.reports.first)
        try expectTrue(DayOverviewBuilder.isReflected(saved), "a saved nonblank answer marks the day reflected")
        let overview = DayOverviewBuilder.overview(dayKey: dayKey, events: Fixtures.dayEvents(count: 4), report: saved, corrections: [])
        try expectTrue(overview.reflected)
    }

    // A save failure surfaces an error and never claims the automatic save succeeded.
    @MainActor
    func saveFailureSurfacesErrorWithoutClaimingSaved() throws {
        let box = ReportBox()
        box.failuresLeft = 1
        let model = makeModel(box: box, report: report(), questions: questions())
        model.updateText("Synthetic draft that cannot be written.", for: "\(dayKey)-q1")
        model.flushPendingSave()
        guard case .failed = model.saveState else {
            throw TestFailure("expected .failed save state, got \(model.saveState)")
        }
        try expectTrue(box.reports.isEmpty, "failed saves must not pretend the store has the draft")
    }

    // Empty day: the note composer works without inventing evidence or questions.
    @MainActor
    func emptyDayAllowsNoteWithoutInventingContent() throws {
        let box = ReportBox()
        let overview = DayOverviewBuilder.overview(dayKey: dayKey, events: [], report: nil, corrections: [])
        try expectTrue(overview.questions.isEmpty)

        let model = makeModel(box: box, report: report(narrative: ""), questions: overview.questions)
        try expectFalse(model.hasQuestions)
        try expectEqual(model.editorAnswerID, ReflectionDraftModel.noteAnswerID(for: dayKey))
        model.updateText("Synthetic free-form note for an empty day.", for: model.editorAnswerID)
        model.flushPendingSave()

        let saved = try require(box.reports.first)
        try expectTrue(DayOverviewBuilder.isReflected(saved), "the authored note marks the day reflected")
        let noteID = ReflectionDraftModel.noteAnswerID(for: dayKey)
        try expectEqual(saved.answers[noteID]?.text, "Synthetic free-form note for an empty day.")
        let reloaded = DayOverviewBuilder.overview(dayKey: dayKey, events: [], report: saved, corrections: [])
        try expectTrue(reloaded.questions.isEmpty, "writing a note must not generate questions")
        try expectNil(reloaded.observedSentence, "a note must not invent observed evidence")
    }

    // Provider output never reaches the report except through the explicit attach action.
    @MainActor
    func analysisAttachesOnlyThroughExplicitAction() throws {
        let box = ReportBox()
        let model = makeModel(box: box, report: report(), questions: questions())
        model.updateText("Synthetic answer kept separate from analysis.", for: "\(dayKey)-q1")
        model.flushPendingSave()
        try expectTrue(box.reports[0].analysisResult == nil, "analysis must not attach itself")

        try expectTrue(model.attachAnalysis("Synthetic labeled analysis output."), "explicit attach persists")
        let saved = try require(box.reports.last)
        try expectEqual(saved.analysisResult, "Synthetic labeled analysis output.")
        try expectTrue(saved.analysisGeneratedAt != nil, "attach records the generation time")
        try expectEqual(saved.answers["\(dayKey)-q1"]?.text, "Synthetic answer kept separate from analysis.",
                        "the authored answer stays intact and separate from the attached analysis")
    }

    // The empty-to-sufficient transition: a saved free-form note keeps its own
    // identity, stays visible and editable, and is never relabeled as a
    // generated question's answer when the day gains suggested questions.
    @MainActor
    func savedNoteStaysVisibleAndEditableWhenDayGainsQuestions() throws {
        let box = ReportBox()
        let noteID = ReflectionDraftModel.noteAnswerID(for: dayKey)

        // Empty day: the user writes a free-form note while no questions exist.
        let empty = makeModel(box: box, report: report(narrative: ""), questions: [])
        let noteText = "Synthetic free-form note about a fictional empty day."
        try expectEqual(empty.editorAnswerID, noteID, "without questions the editor writes the day note")
        empty.updateText(noteText, for: noteID)
        empty.flushPendingSave()
        let savedBefore = try require(box.reports.first)
        try expectEqual(savedBefore.answers[noteID]?.text, noteText)

        // Import transition: the day becomes sufficient, so suggested questions
        // now exist while the stored report still carries the note.
        let suggested = questions()
        let transitioned = makeModel(box: box, report: savedBefore, questions: suggested)
        try expectTrue(transitioned.hasQuestions)
        try expectEqual(transitioned.editorAnswerID, "\(dayKey)-q1",
                        "questions become the primary editor target after the transition")
        try expectTrue(transitioned.showsNoteEditor,
                       "the saved note must stay visible after questions appear")
        try expectTrue(transitioned.canCommit,
                       "Save stays available because the note editor holds text")
        try expectEqual(transitioned.text(for: noteID), noteText,
                        "note text must survive the transition verbatim under its own ID")
        for question in suggested {
            try expectTrue(ReflectionDraftModel.isBlankAnswer(transitioned.text(for: question.id)),
                           "the note must never be relabeled as an answer to \(question.id)")
        }

        // The note remains editable under its own identity.
        let revised = noteText + " Revised after questions appeared."
        transitioned.updateText(revised, for: noteID)
        transitioned.flushPendingSave()
        let savedAfter = try require(box.reports.last)
        try expectEqual(savedAfter.answers[noteID]?.text, revised,
                        "edits keep the note under its own day-note ID")
        for question in suggested {
            try expectNil(savedAfter.answers[question.id],
                          "no answer may be invented for a generated question by saving the note")
        }
    }

    // Save is enabled while any visible editor holds committable text.
    @MainActor
    func canCommitReflectsNoteOrQuestionAnswerText() throws {
        let box = ReportBox()
        let noteID = ReflectionDraftModel.noteAnswerID(for: dayKey)

        // Questions only, nothing written: Save is disabled.
        let questionsOnly = makeModel(box: box, report: report(), questions: questions())
        try expectFalse(questionsOnly.canCommit, "a blank question editor cannot commit")
        questionsOnly.updateText("Synthetic authored answer.", for: "\(dayKey)-q1")
        try expectTrue(questionsOnly.canCommit, "nonblank question text can commit")

        // Questions plus a saved note: a blank question editor still commits
        // through the visible note editor.
        var withNoteReport = report()
        withNoteReport.answers[noteID] = AnswerEntry(text: "Synthetic saved note.", updatedAt: Fixtures.referenceDate)
        let withNote = makeModel(box: box, report: withNoteReport, questions: questions())
        try expectTrue(withNote.showsNoteEditor)
        try expectTrue(ReflectionDraftModel.isBlankAnswer(withNote.text(for: "\(dayKey)-q1")))
        try expectTrue(withNote.canCommit, "the note keeps Save available")

        // Starting a note on a question day reveals the note editor too.
        let fresh = makeModel(box: box, report: report(), questions: questions())
        try expectFalse(fresh.showsNoteEditor, "no note editor until a note exists or is started")
        fresh.updateText("Synthetic in-progress note.", for: noteID)
        try expectTrue(fresh.showsNoteEditor, "writing a note makes its editor visible")
    }

    // MARK: - Evidence context continuity (Task E1)

    /// One synthetic record that arrives after the composer already opened.
    private func lateArrivingEvent(base: Date) -> EvidenceEvent {
        EvidenceEvent(
            id: "fixture-event-imported-late",
            sourceKind: .codex,
            sourceName: "Codex CLI",
            timestamp: base.addingTimeInterval(600),
            timestampApproximate: false,
            kind: .userMessage,
            summary: "Synthetic record that arrived after the composer opened.",
            detail: "",
            evidencePath: "/tmp/reflect-fixture/late.jsonl",
            evidenceLine: 1,
            observedAttribution: .unclear,
            observedAttributionNote: "Structural role in transcript",
            importedAt: base
        )
    }

    // Unchanged selected-day evidence never shows the context-changed notice —
    // not for reorderings and not for unrelated store/report churn, which
    // re-render Today with the same day evidence signature.
    @MainActor
    func unchangedEvidenceNeverMarksContextChanged() throws {
        let box = ReportBox()
        let base = try require(Fmt.date(fromDayKey: dayKey), "fixture day must parse")
        let events = Fixtures.dayEvents(count: 4, base: base)
        let signature = ReflectionDraftModel.evidenceSignature(for: events)
        try expectFalse(signature.isEmpty, "the signature is derived from the day's record ids")

        let model = makeModel(box: box, report: report(), questions: questions(), evidenceSignature: signature)
        try expectFalse(model.isEvidenceContextChanged, "a freshly opened composer shows no notice")

        // Today re-renders while the user writes: a report autosave, a
        // correction, or an import for other days — all recompute the same
        // signature for this day. Record order is not evidence identity.
        model.noteEvidenceChanged(to: ReflectionDraftModel.evidenceSignature(for: Array(events.reversed())))
        model.noteEvidenceChanged(to: signature)
        try expectFalse(model.isEvidenceContextChanged,
                        "unchanged day evidence must never show the context-changed notice")
        try expectTrue(box.reports.isEmpty, "context tracking must never save by itself")
    }

    // New evidence for the selected day marks the context changed while the
    // exact active question, its selection, and every draft stay untouched —
    // nothing is regenerated, reselected, or silently saved.
    @MainActor
    func importedEvidenceMarksContextChangedWithoutTouchingQuestionOrDraft() throws {
        let box = ReportBox()
        let base = try require(Fmt.date(fromDayKey: dayKey), "fixture day must parse")
        let events = Fixtures.dayEvents(count: 4, base: base)
        let model = makeModel(
            box: box,
            report: report(),
            questions: questions(),
            evidenceSignature: ReflectionDraftModel.evidenceSignature(for: events)
        )

        // The user picked the alternate question and wrote before the import.
        model.selectNextQuestion()
        let activeID = "\(dayKey)-q2"
        try expectEqual(model.selectedQuestion?.id, activeID)
        try expectEqual(model.editorAnswerID, activeID)
        let q1Draft = "Synthetic earlier draft for the first question."
        let q2Draft = "Synthetic draft for the second question — kept byte-for-byte."
        model.updateText(q1Draft, for: "\(dayKey)-q1")
        model.updateText(q2Draft, for: activeID)
        model.flushPendingSave()
        try expectEqual(box.reports.count, 1, "the flush save is the only save before the import")

        // Import completes while Today remains visible: the store publishes
        // the same day plus one newly imported record.
        let imported = events + [lateArrivingEvent(base: base)]
        let beforeSignature = ReflectionDraftModel.evidenceSignature(for: events)
        let afterSignature = ReflectionDraftModel.evidenceSignature(for: imported)
        try expectNotEqual(afterSignature, beforeSignature, "newly imported day evidence changes the identity")
        try expectEqual(afterSignature, ReflectionDraftModel.evidenceSignature(for: Array(imported.reversed())),
                        "the same record set must not produce a different signature")

        model.noteEvidenceChanged(to: afterSignature)
        try expectTrue(model.isEvidenceContextChanged,
                       "newly imported selected-day evidence must mark the context changed")

        // The exact active question, selection, and drafts are preserved.
        try expectEqual(model.selectedQuestionIndex, 1, "the selected alternate stays selected")
        try expectEqual(model.selectedQuestion?.id, activeID, "the active question is not replaced")
        try expectEqual(model.selectedQuestion, questions()[1], "the active question object is unchanged, not regenerated")
        try expectEqual(model.questions, questions(), "the question list is not refreshed or reselected")
        try expectEqual(model.editorAnswerID, activeID, "the visible editor keeps its identity")
        try expectEqual(model.text(for: activeID), q2Draft, "the active draft survives byte-for-byte")
        try expectEqual(model.text(for: "\(dayKey)-q1"), q1Draft, "the other draft survives byte-for-byte")
        try expectEqual(box.reports.count, 1, "marking the context changed must never save silently")
    }

    // Route away from Today with a pending debounced draft: the composer's
    // disappearance flushes it to the store; returning to the same day
    // recreates the composer and restores the draft byte-for-byte.
    @MainActor
    func routeAwayAndBackFlushesPendingDraftAndRestoresByteForByte() throws {
        let box = ReportBox()
        let events = Fixtures.dayEvents(count: 4)
        let signature = ReflectionDraftModel.evidenceSignature(for: events)

        let composer = makeModel(box: box, report: report(), questions: questions(), evidenceSignature: signature)
        let exactDraft = "Synthetic draft typed right before leaving Today — restored verbatim."
        composer.updateText(exactDraft, for: "\(dayKey)-q1")
        try expectEqual(composer.saveState, .saving, "an edit leaves a pending debounced save")

        // The route leaves Today: ReflectionComposerView.onDisappear runs the
        // same flushPendingSave() call modeled here.
        composer.flushPendingSave()
        try expectEqual(box.reports.count, 1, "disappearance must flush the pending draft")
        let stored = try require(box.reports.first)
        try expectEqual(stored.answers["\(dayKey)-q1"]?.text, exactDraft,
                        "the store receives the draft byte-for-byte")

        // The route returns to the same day: TodayView.loadComposer recreates
        // the composer from the persisted report.
        let returning = makeModel(box: box, report: stored, questions: questions(), evidenceSignature: signature)
        try expectEqual(returning.text(for: "\(dayKey)-q1"), exactDraft,
                        "returning restores the draft byte-for-byte")
        try expectEqual(returning.answers["\(dayKey)-q1"], exactDraft,
                        "the recreated model holds exactly the stored answer")
        try expectFalse(returning.isEvidenceContextChanged,
                        "returning to the same unchanged evidence shows no notice")
    }

    static var entries: [TestEntry] {
        let tests = ReflectionDraftTests()
        return [
            TestEntry(suite: suiteName, name: "generatedNarrativeIsNeverPrefilledIntoComposer") {
                try MainActor.assumeIsolated { try tests.generatedNarrativeIsNeverPrefilledIntoComposer() }
            },
            TestEntry(suite: suiteName, name: "draftsSurviveImmediateDaySwitchAndReturn") {
                try MainActor.assumeIsolated { try tests.draftsSurviveImmediateDaySwitchAndReturn() }
            },
            TestEntry(suite: suiteName, name: "tryingAnotherQuestionPreservesBothAnswers") {
                try MainActor.assumeIsolated { try tests.tryingAnotherQuestionPreservesBothAnswers() }
            },
            TestEntry(suite: suiteName, name: "blankSavesAreRejectedAndNonblankMarksReflected") {
                try MainActor.assumeIsolated { try tests.blankSavesAreRejectedAndNonblankMarksReflected() }
            },
            TestEntry(suite: suiteName, name: "saveFailureSurfacesErrorWithoutClaimingSaved") {
                try MainActor.assumeIsolated { try tests.saveFailureSurfacesErrorWithoutClaimingSaved() }
            },
            TestEntry(suite: suiteName, name: "emptyDayAllowsNoteWithoutInventingContent") {
                try MainActor.assumeIsolated { try tests.emptyDayAllowsNoteWithoutInventingContent() }
            },
            TestEntry(suite: suiteName, name: "analysisAttachesOnlyThroughExplicitAction") {
                try MainActor.assumeIsolated { try tests.analysisAttachesOnlyThroughExplicitAction() }
            },
            TestEntry(suite: suiteName, name: "savedNoteStaysVisibleAndEditableWhenDayGainsQuestions") {
                try MainActor.assumeIsolated { try tests.savedNoteStaysVisibleAndEditableWhenDayGainsQuestions() }
            },
            TestEntry(suite: suiteName, name: "canCommitReflectsNoteOrQuestionAnswerText") {
                try MainActor.assumeIsolated { try tests.canCommitReflectsNoteOrQuestionAnswerText() }
            },
            TestEntry(suite: suiteName, name: "unchangedEvidenceNeverMarksContextChanged") {
                try MainActor.assumeIsolated { try tests.unchangedEvidenceNeverMarksContextChanged() }
            },
            TestEntry(suite: suiteName, name: "importedEvidenceMarksContextChangedWithoutTouchingQuestionOrDraft") {
                try MainActor.assumeIsolated { try tests.importedEvidenceMarksContextChangedWithoutTouchingQuestionOrDraft() }
            },
            TestEntry(suite: suiteName, name: "routeAwayAndBackFlushesPendingDraftAndRestoresByteForByte") {
                try MainActor.assumeIsolated { try tests.routeAwayAndBackFlushesPendingDraftAndRestoresByteForByte() }
            }
        ]
    }
}
