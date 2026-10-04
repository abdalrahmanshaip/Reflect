import SwiftUI

/// Design A source-list sidebar: reflection views on top (Today, This Week,
/// Patterns), then Earlier recent days with reflection status, then Evidence
/// (All Records, Sources). Settings is a footer action.
struct ReflectSidebarView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selection: ReflectRoute?

    private let recentDayLimit = 8

    private var recentDays: [RecentDay] {
        let todayKey = Fmt.dayKey(Date())
        return store.recentDays(limit: recentDayLimit + 1)
        .filter { $0.dayKey != todayKey }
        .prefix(recentDayLimit)
        .map { $0 }
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                NavigationLink(value: ReflectRoute.conversation) {
                    Label("Conversation", systemImage: "bubble.left.and.text.bubble.right")
                }
                NavigationLink(value: ReflectRoute.today) {
                    Label("Today", systemImage: "circle.dashed.inset.filled")
                }
                NavigationLink(value: ReflectRoute.week) {
                    Label("This Week", systemImage: "calendar")
                }
                NavigationLink(value: ReflectRoute.patterns) {
                    Label("Patterns", systemImage: "chart.xyaxis.line")
                }
            }

            Section("Earlier") {
                if recentDays.isEmpty {
                    Text("No days yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(recentDays) { day in
                    NavigationLink(value: ReflectRoute.day(dayKey: day.dayKey)) {
                        RecentDayRow(day: day)
                    }
                }
            }

            Section("Evidence") {
                NavigationLink(value: ReflectRoute.allRecords(dayKey: nil)) {
                    Label("All Records", systemImage: "list.bullet")
                }
                NavigationLink(value: ReflectRoute.sources) {
                    Label("Sources", systemImage: "externaldrive")
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(ReflectPalette.sidebar)
        // Keeps Earlier rows readable ("Mon 28 Sep · Reflected") even when the
        // window is narrow or the inspector is open; the detail column absorbs
        // the difference.
        .navigationSplitViewColumnWidth(min: 224, ideal: 232, max: 320)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Everything is stored on this Mac.")
                Text(store.settings.aiEnabled ? "AI analysis is available and only runs when you start it." : "AI analysis is off.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            settingsFooterButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(ReflectPalette.sidebar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    /// Both entry points reach the same settings state: on macOS 14+ the
    /// footer opens the native Settings scene window via the documented
    /// environment action; on macOS 13 it falls back to the in-window
    /// Settings route backed by the same AppStore.
    @ViewBuilder
    private var settingsFooterButton: some View {
        if #available(macOS 14.0, *) {
            NativeSettingsFooterButton(isSelected: selection == .settings)
        } else {
            Button {
                selection = .settings
            } label: {
                SidebarSettingsFooterLabel(isSelected: selection == .settings)
            }
            .buttonStyle(.plain)
            .reflectClickableHover(RoundedRectangle(cornerRadius: 6))
            .accessibilityIdentifier("sidebar-settings-button")
        }
    }
}

/// Shared rendering for the sidebar Settings footer action so both
/// availability variants look and behave identically.
struct SidebarSettingsFooterLabel: View {
    let isSelected: Bool

    var body: some View {
        Label("Settings", systemImage: "gearshape")
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                isSelected ? Color.primary.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// macOS 14+ footer variant: opens the native Settings scene window.
@available(macOS 14.0, *)
private struct NativeSettingsFooterButton: View {
    @Environment(\.openSettings) private var openSettings
    let isSelected: Bool

    var body: some View {
        Button {
            openSettings()
        } label: {
            SidebarSettingsFooterLabel(isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .reflectClickableHover(RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("sidebar-settings-button")
    }
}

/// One "Earlier" row: compact day label, reflection dot (teal when you
/// reflected, hollow when not), and an honest status word.
struct RecentDayRow: View {
    let day: RecentDay

    var body: some View {
        HStack(spacing: 8) {
            Text(Fmt.sidebarDayLabel(day.dayKey))
                .font(.body)
            ReflectionDot(reflected: day.reflected)
            Spacer()
            Text(day.statusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Fmt.sidebarDayLabel(day.dayKey)), \(day.statusLabel)")
    }
}

/// Teal dot for reflected days, hollow ring otherwise — the Design A "Yours" mark.
struct ReflectionDot: View {
    let reflected: Bool

    var body: some View {
        Circle()
            .fill(reflected ? Color.teal : Color.clear)
            .overlay(
                Circle().strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1)
                    .opacity(reflected ? 0 : 1)
            )
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }
}
