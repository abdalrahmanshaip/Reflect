import SwiftUI

/// State machine for the optional AI analysis workflow. Opening, selecting, and
/// paging only mutate local sets — an agent process is touched exclusively
/// inside an explicit Run that passes status and selection checks.
@MainActor
final class OptionalAnalysisModel: ObservableObject {
    public enum RunState: Equatable {
        case idle
        case running
        case finished(text: String, info: String)
        case failed(String)
        /// The run stopped through cancellation (a thrown CancellationError).
        /// No live subprocess cancellation exists yet, so this state never
        /// claims who canceled the run — only that its transmission outcome is
        /// unknown.
        case cancelled
        case restored(text: String, generatedAt: Date?)
    }

    @Published public private(set) var selectedEventIDs: Set<String> = []
    @Published public private(set) var page: Int = 0
    @Published public private(set) var runState: RunState = .idle

    let pageSize = 25

    private let statusProvider: () -> AnalysisService.Status
    private let settingsProvider: () -> AppSettings
    private let agentProvider: () -> AnalysisAgentStatus?
    private let runner: ([EvidenceEvent], AppSettings, AnalysisAgentStatus) async throws -> AnalysisResult

    init(
        statusProvider: @escaping () -> AnalysisService.Status,
        settingsProvider: @escaping () -> AppSettings,
        agentProvider: @escaping () -> AnalysisAgentStatus?,
        runner: @escaping ([EvidenceEvent], AppSettings, AnalysisAgentStatus) async throws -> AnalysisResult
    ) {
        self.statusProvider = statusProvider
        self.settingsProvider = settingsProvider
        self.agentProvider = agentProvider
        self.runner = runner
    }

    // Local-only mutations: no network, no Keychain.
    func toggle(_ eventID: String) {
        if selectedEventIDs.contains(eventID) {
            selectedEventIDs.remove(eventID)
        } else {
            selectedEventIDs.insert(eventID)
        }
    }

    func clearSelection() {
        selectedEventIDs.removeAll()
    }

    func setPage(_ newPage: Int, pageCount: Int) {
        guard pageCount > 0 else { page = 0; return }
        page = min(max(newPage, 0), pageCount - 1)
    }

    var selectionCount: Int { selectedEventIDs.count }

    var canRun: Bool {
        guard runState != .running, !selectedEventIDs.isEmpty else { return false }
        if case .ready = statusProvider() { return true }
        return false
    }

    /// Truthful status copy. A non-idle operation state (running, finished,
    /// failed, canceled, restored) is always visible — a later availability
    /// change must never hide what an earlier run actually did — and the
    /// current disabled/incomplete configuration is appended to it without
    /// replacing it. The idle state speaks only to current availability (or,
    /// when ready, the explicit-run trigger for this view).
    var statusText: String {
        switch statusProvider() {
        case .disabled:
            let availability = "AI analysis is disabled (default). No network calls are made. Enable and configure it in Settings."
            if runState == .idle { return availability }
            return "\(operationStatus) \(availability)"
        case .incomplete(let reason):
            let availability = "AI is enabled but not fully configured: \(reason) Configure it in Settings."
            if runState == .idle { return availability }
            return "\(operationStatus) \(availability)"
        case .ready:
            if runState == .idle { return readyIdleStatus }
            return operationStatus
        }
    }

    private var readyIdleStatus: String {
        "Configured. No analysis has run in this view yet; selected records are sent to the agent's service only when you explicitly run an analysis."
    }

    /// Operation copy for a non-idle run state. Each state states only what is
    /// actually known: an in-flight run is sending now; a finished run sent
    /// the selected records (usage and cost stay unknown because the agent
    /// does not report them); a failed attempt may already have transmitted
    /// data, so its outcome is stated as unknown; a canceled run is reported
    /// separately from an ordinary failure because some or all records may
    /// already have been sent; and a restored result is storage from an
    /// earlier run, never a new invocation.
    private var operationStatus: String {
        switch runState {
        case .idle:
            return readyIdleStatus
        case .running:
            return "Sending the selected records to the agent's service now."
        case .finished:
            return "The selected records were sent to the agent's service when you ran the analysis. Token usage and cost are not reported."
        case .failed:
            return "The last analysis attempt did not complete, so whether the selected records reached the agent's service is unknown."
        case .cancelled:
            return "The analysis run was canceled before completing, so some or all of the selected records may already have been sent; whether they reached the agent's service is unknown."
        case .restored(_, let generatedAt):
            var line = "Showing the analysis result saved with this day's report from an earlier run — no new analysis was invoked."
            if let generatedAt {
                line += " Original run: \(Fmt.dateTime(generatedAt))."
            }
            return line
        }
    }

    /// Restores an analysis previously attached through the explicit Run/Attach
    /// flow, so reopening a day shows the stored labeled result. Reads only the
    /// report the caller already holds — no Keychain and no network access.
    public func restoreAttached(from report: DailyReport) {
        guard let stored = report.analysisResult,
              !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        runState = .restored(text: stored, generatedAt: report.analysisGeneratedAt)
    }

    /// Whether records for this day have been (or are being) sent this session:
    /// only an explicit Run sends anything. A canceled or failed run reports
    /// false here because its transmission outcome is unknown, not because a
    /// send is ruled out — the privacy note states that unknown separately.
    var hasSentRecordsThisSession: Bool {
        switch runState {
        case .running, .finished: return true
        case .idle, .failed, .cancelled, .restored: return false
        }
    }

    var isRunInFlight: Bool {
        if case .running = runState { return true }
        return false
    }

    var hasFailedRun: Bool {
        if case .failed = runState { return true }
        return false
    }

    /// Explicit Run. Selecting and opening never reaches this process boundary.
    /// A thrown CancellationError lands in `.cancelled` — a distinct state from
    /// an ordinary failure, because the request may already have transmitted
    /// some or all selected records. This is state handling only; it is not
    /// live subprocess cancellation, and no Cancel button is offered.
    func run(selectedEvents: [EvidenceEvent]) async {
        guard canRun else { return }
        runState = .running
        do {
            let settings = settingsProvider()
            guard let agent = agentProvider() else {
                runState = .failed("The selected analysis agent is not ready.")
                return
            }
            let result = try await runner(selectedEvents, settings, agent)
            let info = "Agent \(result.agent.displayName) · model \(result.model)."
            runState = .finished(text: result.text, info: info)
        } catch is CancellationError {
            runState = .cancelled
        } catch {
            runState = .failed(error.localizedDescription)
        }
    }
}

/// The secondary AI-analysis workflow: clearly optional, closed by default,
/// explicit selection, and an explicit attach action.
struct OptionalAnalysisView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject var model: OptionalAnalysisModel
    let events: [EvidenceEvent]
    let onAttach: (String) -> Void

    private var pageCount: Int { EventPage.pageCount(total: events.count, pageSize: model.pageSize) }
    private var pageRange: Range<Int> { EventPage.range(total: events.count, page: model.page, pageSize: model.pageSize) }
    private var pageEvents: [EvidenceEvent] {
        EventPage.items(events, page: model.page, pageSize: model.pageSize)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.statusText)
                .font(.callout)
                .foregroundStyle(.secondary)

            if !events.isEmpty {
                Text("Select the evidence records to include. Only selected records are ever sent:")
                    .font(.callout)

                selectionToolbar
                selectionList
                    HStack {
                    Button("Run analysis on selected evidence") {
                        let selected = events.filter { model.selectedEventIDs.contains($0.id) }
                        Task { await model.run(selectedEvents: selected) }
                    }
                    .buttonStyle(ProminentButtonStyle())
                    .disabled(!model.canRun)
                    .accessibilityLabel("Run analysis on selected evidence")

                    if !model.selectedEventIDs.isEmpty {
                        Button("Clear selection") { model.clearSelection() }
                            .buttonStyle(.link)
                    }
                    if case .running = model.runState {
                        ProgressView()
                            .scaleEffect(0.6)
                    }
                }
            }

            resultSection
        }
    }

    private var selectionToolbar: some View {
        HStack {
            Text("Showing \(pageRange.lowerBound + 1)–\(pageRange.upperBound) of \(events.count) · \(model.selectionCount) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if pageCount > 1 {
                Button("Previous") { model.setPage(model.page - 1, pageCount: pageCount) }
                    .disabled(model.page == 0)
                Text("\(model.page + 1) of \(pageCount)")
                    .font(.caption.monospacedDigit())
                Button("Next") { model.setPage(model.page + 1, pageCount: pageCount) }
                    .disabled(model.page >= pageCount - 1)
            }
        }
    }

    private var selectionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(pageEvents) { event in
                Toggle(isOn: selectionBinding(for: event)) {
                    EventRow(event: event, attribution: store.effectiveAttribution(for: event))
                }
            }
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if case .finished(let text, let info) = model.runState {
            VStack(alignment: .leading, spacing: 4) {
                EvidenceLabelBadge(label: .inference)
                TextEditor(text: .constant(text))
                    .font(.body)
                    .frame(minHeight: 120)
                    .border(Color.secondary.opacity(0.2))
                    .accessibilityLabel("Analysis result (app-generated inference)")
                Text(info)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Attach result to this day's report") {
                    onAttach(text)
                }
                .accessibilityHint("Stores the labeled analysis result with this day's report")
            }
        } else if case .restored(let text, let generatedAt) = model.runState {
            VStack(alignment: .leading, spacing: 4) {
                EvidenceLabelBadge(label: .inference)
                TextEditor(text: .constant(text))
                    .font(.body)
                    .frame(minHeight: 120)
                    .border(Color.secondary.opacity(0.2))
                    .accessibilityLabel("Saved analysis result (app-generated inference)")
                Text(restoredInfoLine(generatedAt: generatedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(restoredInfoLine(generatedAt: generatedAt))
            }
        } else if case .failed(let message) = model.runState {
            Text("Analysis failed: \(message)")
                .font(.callout)
                .foregroundStyle(.red)
        }
    }

    /// The restored result was already attached through the explicit Run/Attach
    /// flow, so it is shown read-only with its provenance — no second Attach
    /// button and no new agent process.
    private func restoredInfoLine(generatedAt: Date?) -> String {
        var line = "Saved with this day's report from an earlier analysis you ran."
        if let generatedAt {
            line += " Generated at \(Fmt.dateTime(generatedAt))."
        }
        return line
    }

    private func selectionBinding(for event: EvidenceEvent) -> Binding<Bool> {
        Binding(
            get: { model.selectedEventIDs.contains(event.id) },
            set: { enabled in model.toggle(event.id) }
        )
    }

}
