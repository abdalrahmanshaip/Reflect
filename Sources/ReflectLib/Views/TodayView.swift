import SwiftUI

/// Design A Today: one observed sentence, compact facts, one suggested question
/// with the user's writing field, then evidence on request. No event list or AI
/// controls precede the sentence and question.
struct TodayView: View {
    @EnvironmentObject private var store: AppStore

    @State private var day: Date
    @State private var composer: ReflectionDraftModel?
    @State private var analysisModel: OptionalAnalysisModel?
    @State private var isEvidenceVisible = false
    @State private var isAnalysisExpanded = false
    @State private var selectedEvent: EvidenceEvent?
    @State private var detailWidth: CGFloat = 0
    /// Routes "Open in All Records" from the inspector to the full filtered list.
    private let onOpenAllRecords: (String) -> Void
    private let evidenceTab: TodayEvidenceInspector.Tab
    /// Sidebar column visibility, so opening the inspector at narrow widths can
    /// collapse the sidebar instead of squeezing the content column.
    var sidebarVisibility: Binding<NavigationSplitViewVisibility>?

    /// Opening a specific local day (sidebar Earlier route) — opening a day only
    /// reads; stored reports are never changed by selection alone.
    init(
        initialDay: Date? = nil,
        showsEvidence: Bool = false,
        evidenceTab: TodayEvidenceInspector.Tab = .sessions,
        analysisExpanded: Bool = false,
        sidebarVisibility: Binding<NavigationSplitViewVisibility>? = nil,
        onOpenAllRecords: @escaping (String) -> Void = { _ in }
    ) {
        _day = State(initialValue: initialDay ?? Date())
        _isEvidenceVisible = State(initialValue: showsEvidence)
        _isAnalysisExpanded = State(initialValue: analysisExpanded)
        self.evidenceTab = evidenceTab
        self.sidebarVisibility = sidebarVisibility
        self.onOpenAllRecords = onOpenAllRecords
    }

    private var dayKey: String { Fmt.dayKey(day) }
    private var isToday: Bool { dayKey == Fmt.dayKey(Date()) }

    var body: some View {
        let projection = store.todayProjection(for: dayKey)
        let evidenceSignature = ReflectionDraftModel.evidenceSignature(for: projection.events)
        GeometryReader { geometry in
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    GeometryReader { contentGeometry in
                        VStack(spacing: 0) {
                            header(availableWidth: contentGeometry.size.width)
                            Divider()
                            ScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            TodayOverviewView(overview: projection.overview)
                            if let composer {
                                ReflectionComposerView(model: composer)
                            }
                            evidenceRow(projection: projection)
                            analysisSection(projection: projection)
                            if let legacy = projection.legacyNarrative {
                                legacyDraftSection(legacy)
                            }
                        }
                            .padding(.horizontal, 48)
                            .padding(.top, 34)
                            .padding(.bottom, 44)
                            .frame(maxWidth: 700, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                    }
                }
                if isEvidenceVisible {
                    Divider()
                    TodayEvidenceInspector(
                        dayKey: dayKey,
                        events: projection.events,
                        initialTab: evidenceTab,
                        onClose: { closeEvidence() },
                        onOpenAllRecords: onOpenAllRecords,
                        projectedGroups: projection.sessions,
                        projectedHourLanes: projection.hourLanes
                    )
                }
            }
            .onChange(of: isEvidenceVisible) { visible in
                guard visible else { return }
                scheduleSidebarCheck()
            }
            .onChange(of: geometry.size.width) { width in
                detailWidth = width
            }
            .onAppear {
                detailWidth = geometry.size.width
                if isEvidenceVisible {
                    // Launch-time opens never fire onChange; re-check after the
                    // window has settled at its final size.
                    scheduleSidebarCheck()
                }
            }
        }
        .onAppear(perform: loadComposer)
        .onChange(of: day) { _ in loadComposer() }
        .onChange(of: evidenceSignature) { signature in
            // Import completed while Today stayed visible: mark the evidence
            // context changed without touching the active question or draft.
            composer?.noteEvidenceChanged(to: signature)
        }
        .sheet(item: $selectedEvent) { event in
            EvidenceSheet(event: event)
        }
    }

    // MARK: Header

    private func header(availableWidth: CGFloat) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(isToday ? "Today" : Fmt.sidebarDayLabel(dayKey))
                    .font(.headline)
                Text(Fmt.fullDate(day))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let composer, availableWidth > 560 {
                ReflectionSaveStatusView(model: composer)
            }
            Button {
                isEvidenceVisible.toggle()
            } label: {
                if availableWidth > 520 {
                    Label("View Evidence", systemImage: "doc.text.magnifyingglass")
                        .labelStyle(.titleAndIcon)
                } else {
                    Label("View Evidence", systemImage: "doc.text.magnifyingglass")
                        .labelStyle(.iconOnly)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .background(isEvidenceVisible ? Color.secondary.opacity(0.12) : Color.clear)
            .accessibilityLabel(isEvidenceVisible ? "Hide evidence inspector" : "Show evidence inspector")
            HStack(spacing: 0) {
                Button {
                    day = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 26, height: 22)
                }
                .accessibilityLabel("Previous day")
                .reflectClickableHover(RoundedRectangle(cornerRadius: 5))
                Divider()
                    .frame(height: 14)
                Button {
                    day = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 26, height: 22)
                        .foregroundStyle(isToday ? Color(nsColor: .disabledControlTextColor) : Color(nsColor: .controlTextColor))
                }
                .disabled(isToday)
                .accessibilityLabel("Next day")
                .reflectClickableHover(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .background(Capsule().fill(ReflectPalette.button))
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.5))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Previous or next day")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    // MARK: Evidence on request

    private func evidenceRow(projection: TodayRouteProjection) -> some View {
        Button {
            isEvidenceVisible.toggle()
        } label: {
            HStack(spacing: 12) {
                ObservedMark()
                VStack(alignment: .leading, spacing: 2) {
                    Text("View evidence")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(projection.evidenceSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isEvidenceVisible ? "chevron.left" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .reflectClickableHover(RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel(isEvidenceVisible ? "Hide evidence" : "View evidence")
        .accessibilityHint(projection.evidenceSubtitle)
    }

    // MARK: Optional AI analysis (secondary; closed by default)

    private func analysisSection(projection: TodayRouteProjection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SuggestedMark()
                analysisStatusLine
            }
            DisclosureGroup(isExpanded: $isAnalysisExpanded) {
                if let analysisModel {
                    OptionalAnalysisView(
                        model: analysisModel,
                        events: projection.sortedEvents,
                        onAttach: { text in
                            composer?.attachAnalysis(text)
                        }
                    )
                    .padding(.top, 12)
                }
            } label: {
                Text("Analyze this day's evidence…")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(ReflectPalette.accent)
            }
            .accessibilityLabel("Analyze this day's evidence with optional AI analysis")
        }
        .padding(.top, 16)
    }

    /// Whether the stored report carries an attached analysis result.
    private var hasStoredAnalysis: Bool {
        !(store.report(for: dayKey).analysisResult ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Truthful privacy status for this day's analysis surface. The line view
    /// subscribes directly to the analysis model's published run state via
    /// @ObservedObject, so it refreshes on every run-state transition (running,
    /// finished, failed) instead of waiting for an unrelated parent re-render.
    @ViewBuilder
    private var analysisStatusLine: some View {
        if let analysisModel {
            AnalysisStatusLine(
                model: analysisModel,
                hasStoredAnalysis: hasStoredAnalysis,
                aiEnabled: store.settings.aiEnabled
            )
        } else {
            let line = AnalysisPrivacyNote.text(aiEnabled: store.settings.aiEnabled, state: .noAttachedResult)
            Text(line)
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityLabel(line)
        }
    }

    /// Subscribes to the model's published operation state and derives the
    /// send state from storage plus that state, so the wording stays accurate
    /// across disabled, configured-not-run, running, run-completed, failed,
    /// and restored-attached days.
    private struct AnalysisStatusLine: View {
        @ObservedObject var model: OptionalAnalysisModel
        let hasStoredAnalysis: Bool
        let aiEnabled: Bool

        private var line: String {
            AnalysisPrivacyNote.text(
                aiEnabled: aiEnabled,
                state: AnalysisPrivacyNote.sendState(hasStoredAnalysis: hasStoredAnalysis, runState: model.runState)
            )
        }

        var body: some View {
            Text(line)
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityLabel(line)
        }
    }

    // MARK: Legacy generated draft (secondary path to older report content)

    private func legacyDraftSection(_ legacy: LegacyNarrativeProjection) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                Text("Generated by Reflect — never counted as your reflection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(legacy.text)
                    .font(.callout)
                    .textSelection(.enabled)
                if let at = legacy.generatedAt {
                    Text("Generated at \(Fmt.dateTime(at)).")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
        } label: {
            Text("Earlier generated draft for this day")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Behavior

    private func closeEvidence() {
        isEvidenceVisible = false
    }

    /// Three columns cannot fit a narrow window: collapse the sidebar so the
    /// day column stays readable when the inspector is open. When the width is
    /// comfortably wide, all columns come back.
    private func scheduleSidebarCheck() {
        collapseSidebarForInspector(detailWidth)
        // Re-check after the window settles at its final size (launch-time opens).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if isEvidenceVisible {
                collapseSidebarForInspector(detailWidth)
            }
        }
    }

    private func collapseSidebarForInspector(_ availableWidth: CGFloat) {
        guard let sidebarVisibility else { return }
        // Thresholds compare the DETAIL width: after collapsing, the detail
        // grows to the full window width, so only >= 900 counts as "room for
        // three columns"; otherwise the check would undo its own collapse.
        if availableWidth < 660 {
            sidebarVisibility.wrappedValue = .detailOnly
        } else if availableWidth >= 900 {
            sidebarVisibility.wrappedValue = .all
        }
    }

    /// Loads (or reloads) the composer and analysis model for the selected day.
    /// The previous day's pending autosave is flushed first, so immediate day
    /// switches never lose drafted text.
    private func loadComposer() {
        composer?.flushPendingSave()
        let store = self.store
        let report = store.report(for: dayKey)
        let overview = store.dayOverview(for: dayKey)
        composer = ReflectionDraftModel(
            dayKey: dayKey,
            report: report,
            questions: overview.questions,
            evidenceSignature: ReflectionDraftModel.evidenceSignature(for: store.events(onDay: dayKey)),
            save: { store.saveReport($0) }
        )
        // Analysis state is day-scoped; closures hold the store reference and
        // only start a verified agent process inside an explicit Run.
        analysisModel = OptionalAnalysisModel(
            statusProvider: { store.aiStatus() },
            settingsProvider: { store.settings },
            agentProvider: {
                guard let selected = store.settings.analysisAgent else { return nil }
                return store.analysisAgentStatus(for: selected)
            },
            runner: { selected, settings, agent in
                // Corrections stay separately persisted; only the corrections
                // for the explicitly selected records reach the payload, and
                // each observed attribution is serialized unchanged.
                try AnalysisService().run(
                    selectedEvents: selected,
                    settings: settings,
                    agent: agent,
                    corrections: store.corrections
                )
            }
        )
        // A previously attached result is surfaced read-only from the stored
        // report — restore reads only this report, never the Keychain/network.
        analysisModel?.restoreAttached(from: report)
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
