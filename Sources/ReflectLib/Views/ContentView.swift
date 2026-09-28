import SwiftUI

public struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selection: Section = .today

    public init() {}

    enum Section: String, CaseIterable, Identifiable, Hashable {
        case today, timeline, weekly, growth, sources, settings

        var id: String { rawValue }

        var label: String {
            switch self {
            case .today: return "Today"
            case .timeline: return "Timeline"
            case .weekly: return "Weekly"
            case .growth: return "Growth"
            case .sources: return "Sources"
            case .settings: return "Settings"
            }
        }

        var symbol: String {
            switch self {
            case .today: return "sun.max"
            case .timeline: return "list.bullet"
            case .weekly: return "calendar"
            case .growth: return "chart.line.uptrend.xyaxis"
            case .sources: return "externaldrive"
            case .settings: return "gearshape"
            }
        }
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(Section.allCases) { section in
                    NavigationLink(value: section) {
                        Label(section.label, systemImage: section.symbol)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Reflect")
        } detail: {
            switch selection {
            case .today: TodayView()
            case .timeline: TimelineView()
            case .weekly: WeeklyView()
            case .growth: GrowthView()
            case .sources: SourcesView()
            case .settings: SettingsView()
            }
        }
        .alert("Something went wrong", isPresented: .init(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
    }
}
