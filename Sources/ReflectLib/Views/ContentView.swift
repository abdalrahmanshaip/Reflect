import SwiftUI

/// Navigation routes behind the Design A sidebar. Day routes carry the stored
/// day key so selection stays stable across imports and report saves.
public enum ReflectRoute: Hashable {
    /// Entry route; the conversation-first home.
    case conversation
    case today
    case week
    case patterns
    case day(dayKey: String)
    /// All Records; carries an optional day filter (from the evidence inspector).
    case allRecords(dayKey: String?)
    case sources
    case settings
}

public struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selection: ReflectRoute?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    private let showsTodayEvidence: Bool
    private let todayEvidenceTab: TodayEvidenceInspector.Tab
    private let showsTodayAnalysis: Bool
    private let expandsLocalData: Bool

    public init(
        initialRoute: ReflectRoute? = nil,
        showsTodayEvidence: Bool = false,
        todayEvidenceTab: TodayEvidenceInspector.Tab = .sessions,
        showsTodayAnalysis: Bool = false,
        expandsLocalData: Bool = false
    ) {
        _selection = State(initialValue: initialRoute ?? .conversation)
        self.showsTodayEvidence = showsTodayEvidence
        self.todayEvidenceTab = todayEvidenceTab
        self.showsTodayAnalysis = showsTodayAnalysis
        self.expandsLocalData = expandsLocalData
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ReflectSidebarView(selection: $selection)
                .navigationTitle("Reflect")
        } detail: {
            detail
                .id(selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ReflectPalette.page)
        }
        .background(ReflectPalette.window)
        .alert("Something went wrong", isPresented: .init(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
    }

    // Route mapping: This Week -> WeeklyView, Patterns -> GrowthView,
    // All Records -> TimelineView; day routes open that exact local day in Today.
    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .conversation:
            ConversationView()
        case .today:
            TodayView(
                showsEvidence: showsTodayEvidence,
                evidenceTab: todayEvidenceTab,
                analysisExpanded: showsTodayAnalysis,
                sidebarVisibility: $columnVisibility,
                onOpenAllRecords: { dayKey in
                    selection = .allRecords(dayKey: dayKey)
                }
            )
        case .week:
            WeeklyView(onOpenDay: { dayKey in
                selection = .day(dayKey: dayKey)
            })
        case .patterns:
            GrowthView()
        case .day(let dayKey):
            TodayView(
                initialDay: Fmt.date(fromDayKey: dayKey) ?? Date(),
                showsEvidence: showsTodayEvidence,
                evidenceTab: todayEvidenceTab,
                analysisExpanded: showsTodayAnalysis,
                sidebarVisibility: $columnVisibility,
                onOpenAllRecords: { filteredDay in
                    selection = .allRecords(dayKey: filteredDay)
                }
            )
        case .allRecords(let dayKey):
            TimelineView(initialDayKey: dayKey)
        case .sources:
            SourcesView()
        case .settings:
            SettingsView(expandsLocalData: expandsLocalData)
        case nil:
            Text("Select a view in the sidebar.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
