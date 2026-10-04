import Foundation
import Combine

/// Save-state machine for the reflection composer. `saved` only ever follows a
/// successful store write; failures surface the reason instead.
public enum ReflectionSaveState: Equatable {
    case idle
    case saving
    case saved(Date)
    case failed(String)
}

/// Owns the user's drafts for one day: per-question answer text, the selected
/// question, autosave debounce, and the save state. Generated report prose is
/// never a draft here — drafts come only from the stored report's answers.
/// The save closure is injected so the logic is testable without a view.
@MainActor
public final class ReflectionDraftModel: ObservableObject {
    @Published public private(set) var answers: [String: String]
    @Published public private(set) var selectedQuestionIndex: Int = 0
    @Published public private(set) var saveState: ReflectionSaveState = .idle

    public let dayKey: String
    public let questions: [SuggestedQuestion]
    private var baseReport: DailyReport
    private let save: (DailyReport) -> Bool
    private var debounceTask: Task<Void, Never>?
    /// Whether the free-form day note editor is visible. The note keeps its own
    /// identity (`<day>-note`) even after generated questions appear: once the
    /// day has a saved note — or the user starts writing one — the editor stays
    /// visible, so the empty-to-sufficient transition never hides user text.
    @Published public private(set) var showsNoteEditor: Bool
    /// True once the selected day's evidence identity changed while this
    /// composer stayed open. Purely informational: the active question, its
    /// selection, and every draft are never touched by it.
    @Published public private(set) var isEvidenceContextChanged: Bool = false
    /// The evidence identity this composer was last synced with.
    private var trackedEvidenceSignature: String

    public init(
        dayKey: String,
        report: DailyReport,
        questions: [SuggestedQuestion],
        evidenceSignature: String = "",
        save: @escaping (DailyReport) -> Bool
    ) {
        self.dayKey = dayKey
        self.questions = questions
        self.baseReport = report
        self.save = save
        self.answers = report.answers.mapValues(\.text)
        self.showsNoteEditor = questions.isEmpty || Self.hasSavedNote(report, dayKey: dayKey)
        self.trackedEvidenceSignature = evidenceSignature
    }

    /// Stable identity signature for one day's evidence: the sorted event ids.
    /// Order-insensitive and day-scoped, so unrelated store/report changes and
    /// imports for other days never change it, while any newly imported record
    /// for the day does. Re-importing the same records is idempotent.
    public static func evidenceSignature(for events: [EvidenceEvent]) -> String {
        events.map(\.id).sorted().joined(separator: "\u{1F}")
    }

    /// Called when Today re-renders with possibly new evidence for this day.
    /// Only a changed evidence identity marks the context changed; the active
    /// question, the selected alternate, and every draft stay exactly as they
    /// are — nothing is regenerated, reselected, or saved here.
    public func noteEvidenceChanged(to signature: String) {
        guard signature != trackedEvidenceSignature else { return }
        trackedEvidenceSignature = signature
        isEvidenceContextChanged = true
    }

    /// Stable answer id for the user-owned note on days without generated questions.
    public static func noteAnswerID(for dayKey: String) -> String {
        "\(dayKey)-note"
    }

    /// Whether the report carries a saved nonblank free-form note.
    public static func hasSavedNote(_ report: DailyReport, dayKey: String) -> Bool {
        guard let entry = report.answers[noteAnswerID(for: dayKey)] else { return false }
        return !isBlankAnswer(entry.text)
    }

    public var hasQuestions: Bool { !questions.isEmpty }

    public var selectedQuestion: SuggestedQuestion? {
        questions.isEmpty ? nil : questions[min(selectedQuestionIndex, questions.count - 1)]
    }

    /// The answer id the visible editor writes to: the selected question, or the
    /// day note when no questions exist.
    public var editorAnswerID: String {
        selectedQuestion?.id ?? Self.noteAnswerID(for: dayKey)
    }

    public func text(for answerID: String) -> String {
        answers[answerID] ?? ""
    }

    public func updateText(_ text: String, for answerID: String) {
        answers[answerID] = text
        if answerID == Self.noteAnswerID(for: dayKey) {
            showsNoteEditor = true
        }
        scheduleAutosave()
    }

    /// Cycles to the next question without touching any answer draft.
    public func selectNextQuestion() {
        guard !questions.isEmpty else { return }
        selectedQuestionIndex = (selectedQuestionIndex + 1) % questions.count
    }

    /// A blank or whitespace-only answer is never a committable reflection.
    public static func isBlankAnswer(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Save is enabled while any visible editor holds committable text: the
    /// question editor when questions exist, the day note when its editor is
    /// shown. Blank answers are dropped on save.
    public var canCommit: Bool {
        var visibleEditors: [String] = []
        if hasQuestions {
            visibleEditors.append(editorAnswerID)
        }
        if showsNoteEditor {
            visibleEditors.append(Self.noteAnswerID(for: dayKey))
        }
        return visibleEditors.contains { !Self.isBlankAnswer(answers[$0] ?? "") }
    }

    /// Explicit commit for the Save Reflection button: refuses blank text and
    /// reports the real save outcome.
    @discardableResult
    public func saveNow() -> Bool {
        debounceTask?.cancel()
        debounceTask = nil
        return persist()
    }

    /// Flushes a pending autosave immediately — used before day/navigation changes.
    public func flushPendingSave() {
        debounceTask?.cancel()
        debounceTask = nil
        if saveState == .saving {
            persist()
        }
    }

    /// Explicitly attaches provider analysis to this day's stored report. Called
    /// only from the user's attach action; the analysis stays a labeled,
    /// separate field and is never mixed into observed summaries or answers.
    @discardableResult
    public func attachAnalysis(_ text: String) -> Bool {
        baseReport.analysisResult = text
        baseReport.analysisGeneratedAt = Date()
        saveState = .saving
        return persist()
    }

    private func scheduleAutosave() {
        saveState = .saving
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let self, !Task.isCancelled else { return }
            self.persist()
        }
    }

    @discardableResult
    private func persist() -> Bool {
        var updated = baseReport
        var merged = updated.answers
        for (id, text) in answers {
            if Self.isBlankAnswer(text) {
                merged.removeValue(forKey: id)
            } else {
                merged[id] = AnswerEntry(text: text, updatedAt: Date())
            }
        }
        updated.answers = merged
        let succeeded = save(updated)
        if succeeded {
            baseReport = updated
            saveState = .saved(Date())
        } else {
            saveState = .failed("Reflect could not write your reflection to disk. It stays in this window; saving again may fix it.")
        }
        return succeeded
    }
}
