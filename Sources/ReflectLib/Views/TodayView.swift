import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: AppStore

    @State private var day = Date()
    @State private var narrative = ""
    @State private var narrativeGeneratedAt: Date?
    @State private var answers: [String: String] = [:]
    @State private var selectedEventIDs: Set<String> = []
    @State private var analysisText = ""
    @State private var analysisInfo = ""
    @State private var analysisRunning = false
    @State private var dirty = false
    @State private var selectedEvent: EvidenceEvent?

    private var dayKey: String { Fmt.dayKey(day) }
    private var dayEvents: [EvidenceEvent] { store.events(onDay: dayKey) }
    private var facts: DayFacts { store.dayFacts(for: dayKey) }
    private var draft: ReportDraft { ReportGenerator.draft(for: facts) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    evidenceSection
                    reportSection
                    questionsSection
                    analysisSection
                }
                .padding(20)
            }
        }
        .onAppear(perform: loadFromStore)
        .onChange(of: day) { _ in loadFromStore() }
        .sheet(item: $selectedEvent) { event in
            EvidenceSheet(event: event)
        }
    }

    private var header: some View {
        HStack {
            DatePicker("Day", selection: $day, displayedComponents: .date)
                .datePickerStyle(.compact)
            Spacer()
            if dirty {
                Text("Unsaved changes")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button("Save report") { saveReport() }
                .disabled(!dirty)
                .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Observed evidence for \(dayKey)", systemImage: "doc.text.magnifyingglass")
                .font(.headline)
            if dayEvents.isEmpty {
                Text("No evidence imported for this day. Use Sources to start an import; nothing is imported automatically.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    ForEach(store.countBySource(for: dayEvents), id: \.0) { kind, count in
                        SourceCountBadge(kind: kind, count: count)
                    }
                }
                Text("\(dayEvents.count) event(s). Click a row for evidence details.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(dayEvents.sorted { $0.timestamp < $1.timestamp }.prefix(12)) { event in
                    EventRow(event: event, attribution: store.effectiveAttribution(for: event))
                        .contentShape(Rectangle())
                        .onTapGesture { selectedEvent = event }
                }
                if dayEvents.count > 12 {
                    Text("… and \(dayEvents.count - 12) more. See Timeline for the full list.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var reportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Daily report", systemImage: "square.and.pencil")
                    .font(.headline)
                if let generatedAt = narrativeGeneratedAt {
                    Text("draft generated \(Fmt.time(generatedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Generate draft") {
                    narrative = draft.narrative
                    narrativeGeneratedAt = Date()
                    dirty = true
                }
                .disabled(dayEvents.isEmpty)
            }
            if draft.insufficientEvidence {
                InsufficientEvidenceBanner(reason: draft.reason ?? "Insufficient evidence.")
            }
            TextEditor(text: $narrative)
                .font(.body)
                .frame(minHeight: 110)
                .border(Color.secondary.opacity(0.25))
                .onChange(of: narrative) { _ in dirty = true }
        }
    }

    private var questionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Coaching questions (deterministic, grounded in this day's evidence)", systemImage: "questionmark.circle")
                .font(.headline)
            if draft.insufficientEvidence {
                Text(draft.reason ?? "No questions without enough evidence.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(draft.questions) { question in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 6) {
                            EvidenceLabelBadge(label: .inference)
                            Text(question.text)
                                .font(.callout.weight(.medium))
                        }
                        TextEditor(text: bindingForAnswer(question.id))
                            .font(.body)
                            .frame(minHeight: 54)
                            .border(Color.secondary.opacity(0.2))
                    }
                }
                Text("Your answers are saved with the report and kept separate from observed evidence.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var analysisSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AI analysis (explicit; nothing is sent unless you run it)", systemImage: "paperplane")
                .font(.headline)
            Text(statusDescription)
                .font(.callout)
                .foregroundStyle(.secondary)

            if !dayEvents.isEmpty {
                Text("Select the evidence records to include. Only selected records are ever sent:")
                    .font(.callout)
                ForEach(dayEvents.sorted { $0.timestamp < $1.timestamp }) { event in
                    Toggle(isOn: selectionBinding(for: event)) {
                        EventRow(event: event, attribution: store.effectiveAttribution(for: event))
                    }
                }
                Text("Rough estimate: \(estimateDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Run analysis on selected evidence") { runAnalysis() }
                        .disabled(!canRunAnalysis)
                    if analysisRunning {
                        ProgressView()
                            .scaleEffect(0.6)
                    }
                }
            }

            if !analysisText.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    EvidenceLabelBadge(label: .inference)
                    TextEditor(text: .constant(analysisText))
                        .font(.body)
                        .frame(minHeight: 120)
                        .border(Color.secondary.opacity(0.2))
                    Text(analysisInfo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Attach result to this day's report") {
                        attachAnalysisToReport()
                    }
                }
            }
        }
    }

    // MARK: Behavior

    private var statusDescription: String {
        switch store.aiStatus() {
        case .disabled:
            return "AI analysis is disabled (default). No network calls are made. Enable and configure it in Settings."
        case .incomplete(let reason):
            return "AI is enabled but not fully configured: \(reason) Configure it in Settings."
        case .ready:
            return "Configured. This has not been verified against a live endpoint until you run an analysis."
        }
    }

    private var canRunAnalysis: Bool {
        if case .ready = store.aiStatus() {
            return !selectedEventIDs.isEmpty && !analysisRunning
        }
        return false
    }

    private var estimateDescription: String {
        let selected = dayEvents.filter { selectedEventIDs.contains($0.id) }
        let payload = AnalysisService.buildPayload(
            model: store.settings.providerModel.isEmpty ? "model" : store.settings.providerModel,
            events: selected,
            instruction: AnalysisService.defaultInstruction,
            maxPreviewCharacters: store.settings.maxPreviewCharacters
        )
        let serialized = (try? JSONSerialization.data(withJSONObject: payload))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let tokens = AnalysisService.estimateTokens(serialized)
        var text = "about \(tokens) input tokens"
        let settings = store.settings
        if settings.pricePerMillionInput > 0 {
            let cost = Double(tokens) / 1_000_000 * settings.pricePerMillionInput
            text += ", roughly \(Fmt.usd(cost)) at the configured input price (output not included)"
        }
        return text
    }

    private func loadFromStore() {
        let report = store.report(for: dayKey)
        narrative = report.narrative
        narrativeGeneratedAt = report.narrativeGeneratedAt
        answers = report.answers.mapValues(\.text)
        analysisText = report.analysisResult ?? ""
        analysisInfo = report.analysisGeneratedAt.map { "Saved result from \(Fmt.dateTime($0))." } ?? ""
        selectedEventIDs = []
        dirty = false
    }

    private func saveReport() {
        var report = store.report(for: dayKey)
        report.narrative = narrative
        report.narrativeGeneratedAt = narrativeGeneratedAt
        var merged = report.answers
        for (id, text) in answers {
            merged[id] = AnswerEntry(text: text, updatedAt: Date())
        }
        report.answers = merged
        store.saveReport(report)
        dirty = false
    }

    private func bindingForAnswer(_ id: String) -> Binding<String> {
        Binding(
            get: { answers[id] ?? "" },
            set: { answers[id] = $0; dirty = true }
        )
    }

    private func selectionBinding(for event: EvidenceEvent) -> Binding<Bool> {
        Binding(
            get: { selectedEventIDs.contains(event.id) },
            set: { enabled in
                if enabled { selectedEventIDs.insert(event.id) } else { selectedEventIDs.remove(event.id) }
            }
        )
    }

    private func runAnalysis() {
        let selected = dayEvents.filter { selectedEventIDs.contains($0.id) }
        guard let apiKey = store.secrets.secret(account: AppConstants.keychainAccount), !apiKey.isEmpty else {
            store.lastError = "No API key is stored in Keychain."
            return
        }
        analysisRunning = true
        let settings = store.settings
        Task {
            defer { analysisRunning = false }
            do {
                let result = try await AnalysisService().run(selectedEvents: selected, settings: settings, apiKey: apiKey)
                analysisText = result.text
                var info = "Model \(result.model) at \(result.endpoint). "
                if let input = result.inputTokens, let output = result.outputTokens {
                    info += "Tokens: \(input) in / \(output) out "
                    info += result.usedRequestedUsage ? "(as requested by provider)." : "(rough local estimate)."
                }
                if let cost = result.estimatedCostUSD {
                    info += " Estimated cost: \(Fmt.usd(cost))."
                }
                analysisInfo = info
                dirty = true
            } catch {
                store.lastError = "Analysis failed: \(error.localizedDescription)"
            }
        }
    }

    private func attachAnalysisToReport() {
        var report = store.report(for: dayKey)
        report.analysisResult = analysisText
        report.analysisGeneratedAt = Date()
        store.saveReport(report)
    }
}

struct EventRow: View {
    let event: EvidenceEvent
    let attribution: (value: Attribution, isCorrected: Bool)

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: event.kind.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(Fmt.time(event.timestamp))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if event.timestampApproximate {
                        Text("~approx.")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    Text(event.summary)
                        .font(.callout)
                        .lineLimit(1)
                }
                Text("\(event.sourceName) · \(event.kind.label) · \(event.evidencePath)\(event.evidenceLine.map { ":\($0)" } ?? "")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            AttributionBadge(value: attribution.value, isCorrected: attribution.isCorrected)
        }
        .padding(.vertical, 3)
    }
}
