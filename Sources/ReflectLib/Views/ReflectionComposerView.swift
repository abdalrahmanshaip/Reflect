import SwiftUI

/// Design A's question card: one suggested question with its evidence basis,
/// the user's own writing field, Save Reflection, and the question switcher.
/// With no generated questions (empty or sparse day) it becomes an honest
/// user-owned note — no evidence or question content is invented.
struct ReflectionComposerView: View {
    @ObservedObject private var model: ReflectionDraftModel

    init(model: ReflectionDraftModel) {
        self.model = model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let question = model.selectedQuestion {
                questionHeader(question)
            } else {
                noteHeader
            }

            if let question = model.selectedQuestion {
                Text(question.text)
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .lineSpacing(3)
                    .accessibilityLabel("Suggested question: \(question.text)")
                HStack(spacing: 6) {
                    SuggestedMark()
                    Text(question.basis)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Based on: \(question.basis)")
            }

            if model.isEvidenceContextChanged {
                evidenceChangedNotice
            }

            reflectionEditor

            if model.hasQuestions && model.showsNoteEditor {
                savedNoteSection
            }

            HStack(spacing: 12) {
                Button("Save Reflection") {
                    model.saveNow()
                }
                .buttonStyle(ProminentButtonStyle())
                .disabled(!model.canCommit)
                .keyboardShortcut("s", modifiers: .command)
                .accessibilityLabel("Save Reflection")

                Spacer()

                if model.questions.count > 1 {
                    Button("Try a different question") {
                        model.selectNextQuestion()
                    }
                    .buttonStyle(.link)
                    .foregroundStyle(ReflectPalette.accent)
                }
            }
        }
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 12).fill(ReflectPalette.card))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(ReflectPalette.outline, lineWidth: 0.5)
        )
        .onDisappear { model.flushPendingSave() }
    }

    private func questionHeader(_ question: SuggestedQuestion) -> some View {
        HStack(spacing: 8) {
            SuggestedMark()
            Text("A question to start with")
                .font(.callout.weight(.semibold))
            Text("suggested by Reflect")
                .font(.caption)
                .foregroundStyle(ReflectPalette.inference)
        }
        .accessibilityElement(children: .combine)
    }

    private var noteHeader: some View {
        HStack(spacing: 8) {
            YourMark()
            Text("Your note for this day")
                .font(.callout.weight(.semibold))
            Text("no generated question — write freely")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// Honest notice when the day's evidence identity changed while Today
    /// stayed visible. The active question and every draft are deliberately
    /// untouched, and the notice never claims the question was regenerated.
    private var evidenceChangedNotice: some View {
        let line = model.hasQuestions
            ? "This day's records changed while you were writing. Your question and draft are unchanged."
            : "This day's records changed while you were writing. Your note is unchanged."
        return HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(ReflectPalette.inference)
            Text(line)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(line)
    }

    private var reflectionEditor: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                YourMark()
                Text(model.hasQuestions ? "Your reflection" : "Your note")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ReflectPalette.yours)
            }
            .accessibilityElement(children: .combine)

            ReflectionEditor(text: binding(for: model.editorAnswerID))
        }
    }

    /// A saved free-form day note keeps its own identity and editor when the
    /// day gains generated questions. It is never relabeled or merged into a
    /// question's answer — it stays visible and editable under `<day>-note`.
    private var savedNoteSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                YourMark()
                Text("Your note for this day")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ReflectPalette.yours)
                Text("kept separately from question answers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            ReflectionEditor(
                label: model.hasQuestions ? "Your note for this day" : "Your note",
                text: binding(for: ReflectionDraftModel.noteAnswerID(for: model.dayKey))
            )
        }
    }

    private func binding(for answerID: String) -> Binding<String> {
        Binding(
            get: { model.text(for: answerID) },
            set: { model.updateText($0, for: answerID) }
        )
    }
}

/// The user-owned text editor. Shows the placeholder only; generated report
/// prose is never placed here.
private struct ReflectionEditor: View {
    let label: String
    @Binding var text: String

    init(label: String = "Your reflection", text: Binding<String>) {
        self.label = label
        _text = text
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.system(size: 16, design: .serif))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 108)
                .background(RoundedRectangle(cornerRadius: 8).fill(ReflectPalette.page))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(ReflectPalette.outline, lineWidth: 0.5)
                )
                .accessibilityLabel(label)
                .accessibilityHint("Write a few sentences. Only you will see this.")
            if text.isEmpty {
                Text("Write a few sentences. Only you will see this.")
                    .font(.system(size: 16, design: .serif))
                    .foregroundStyle(Color(nsColor: .placeholderTextColor))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// Header save-status observed separately so the toolbar stays truthful while
/// the composer owns the draft.
struct ReflectionSaveStatusView: View {
    @ObservedObject var model: ReflectionDraftModel

    var body: some View {
        switch model.saveState {
        case .idle:
            Text("Saved automatically")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .saving:
            Text("Saving…")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .saved:
            Text("Saved automatically")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Saved")
        case .failed(let message):
            // The draft text stays in the editors on failure; Retry re-runs
            // the same save without clearing anything.
            HStack(spacing: 8) {
                Text("Couldn't save")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .help(message)
                    .accessibilityLabel("Couldn't save: \(message)")
                Button("Retry") {
                    model.saveNow()
                }
                .buttonStyle(.link)
                .font(.caption)
                .disabled(!model.canCommit)
                .accessibilityLabel("Retry saving the reflection")
            }
        }
    }
}
