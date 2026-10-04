import SwiftUI

/// Design A evidence inspector for the selected day: Sessions and By hour tabs,
/// observed-facts caption, per-record detail + correction via the existing
/// evidence sheet, and explicit routes to the complete All Records path.
public struct TodayEvidenceInspector: View {
    @EnvironmentObject private var store: AppStore
    let dayKey: String
    let events: [EvidenceEvent]
    let onClose: () -> Void
    let onOpenAllRecords: (_ dayKey: String) -> Void
    private let projectedGroups: [EvidenceGroup]?
    private let projectedHourLanes: [(source: SourceKind, marks: [EvidenceHourMark])]?

    public enum Tab: Hashable { case sessions, byHour }
    @State private var tab: Tab
    @State private var expandedGroupIDs: Set<String> = []
    @State private var selectedEvent: EvidenceEvent?

    public init(
        dayKey: String,
        events: [EvidenceEvent],
        initialTab: Tab = .sessions,
        onClose: @escaping () -> Void,
        onOpenAllRecords: @escaping (_ dayKey: String) -> Void,
        projectedGroups: [EvidenceGroup]? = nil,
        projectedHourLanes: [(source: SourceKind, marks: [EvidenceHourMark])]? = nil
    ) {
        self.dayKey = dayKey
        self.events = events
        self.onClose = onClose
        self.onOpenAllRecords = onOpenAllRecords
        self.projectedGroups = projectedGroups
        self.projectedHourLanes = projectedHourLanes
        _tab = State(initialValue: initialTab)
    }

    public var body: some View {
        let groups = projectedGroups ?? EvidenceGroups.sessions(for: events.sorted { $0.timestamp < $1.timestamp })
        let hourLanes = projectedHourLanes ?? EvidenceTimeline.lanes(for: events)
        let hasCommits = events.contains { $0.kind == .gitCommit || $0.sourceKind == .gitLocal }
        VStack(spacing: 0) {
            header
            tabs
            caption
            Divider()
            switch tab {
            case .sessions:
                sessionsList(groups: groups)
            case .byHour:
                EvidenceByHourView(lanes: hourLanes)
            }
            Divider()
            footer(hasCommits: hasCommits)
        }
        .frame(minWidth: 320, idealWidth: 392, maxWidth: 480, maxHeight: .infinity)
        .background(ReflectPalette.window)
        .sheet(item: $selectedEvent) { event in
            EvidenceSheet(event: event)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ObservedMark()
            Text("Evidence")
                .font(.callout.weight(.semibold))
            Text(Fmt.sidebarDayLabel(dayKey))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .reflectClickableHover(RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(.secondary)
            .accessibilityLabel("Close evidence inspector")
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var tabs: some View {
        Picker("Evidence view", selection: $tab) {
            Text("Sessions").tag(Tab.sessions)
            Text("By hour").tag(Tab.byHour)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .accessibilityLabel("Evidence inspector view")
    }

    private var caption: some View {
        Text("Observed in files on this Mac. Counts show what was recorded, not effort or skill.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
    }

    private func sessionsList(groups: [EvidenceGroup]) -> some View {
        Group {
            if groups.isEmpty {
                VStack(spacing: 8) {
                    Text("No records are imported for this day.")
                        .font(.callout)
                    Text("Use Sources to import explicitly; nothing is imported automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groups) { group in
                        Section {
                            if expandedGroupIDs.contains(group.id) {
                                groupRows(group)
                            }
                        } header: {
                            groupHeader(group)
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(ReflectPalette.window)
            }
        }
    }

    private func groupHeader(_ group: EvidenceGroup) -> some View {
        Button {
            if !toggleExpanded(group.id) {
                expandedGroupIDs.insert(group.id)
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: expandedGroupIDs.contains(group.id) ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                Text(EvidenceGroups.timeRangeLabel(for: group.events))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 88, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(group.isCommitMetadata ? ReflectPalette.inference : .primary)
                    if let subtitle = group.subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
                Text("\(group.events.count) record\(group.events.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.trailing, 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .reflectClickableHover(RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel("\(group.title), \(group.events.count) records, \(expandedGroupIDs.contains(group.id) ? "expanded" : "collapsed")")
        .accessibilityHint("Shows the records in this group")
    }

    /// Bounded per-group rendering: only the first rows render here; the rest
    /// stays reachable through the explicit Show all route in All Records.
    private func groupRows(_ group: EvidenceGroup) -> some View {
        let visible = group.events.prefix(EvidenceGroups.initialVisibleRowCount)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(visible) { event in
                Button {
                    selectedEvent = event
                } label: {
                    EventRow(event: event, attribution: store.effectiveAttribution(for: event))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .reflectClickableHover(RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel(recordLabel(for: event))
            }
            if group.events.count > visible.count {
                Button("Show all \(group.events.count) records") {
                    onOpenAllRecords(dayKey)
                }
                .buttonStyle(.link)
                .font(.caption)
                .padding(.vertical, 4)
                .accessibilityHint("Opens the complete list for this day in All Records")
            }
        }
        .padding(.leading, 20)
    }

    private func footer(hasCommits: Bool) -> some View {
        HStack(spacing: 10) {
            Text(hasCommits
                 ? "Commits are metadata. They don't show who wrote the code."
                 : "Observed records only. Attribution corrections stay separate.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Open in All Records") {
                onOpenAllRecords(dayKey)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(events.isEmpty)
            .accessibilityHint("Opens the complete filtered list for this day")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func toggleExpanded(_ id: String) -> Bool {
        if expandedGroupIDs.contains(id) {
            expandedGroupIDs.remove(id)
            return true
        }
        return false
    }

    private func recordLabel(for event: EvidenceEvent) -> String {
        let resolved = store.effectiveAttribution(for: event)
        return RowAccessibility.recordRowLabel(
            time: Fmt.time(event.timestamp),
            summary: event.summary,
            attribution: resolved.value.label,
            isCorrected: resolved.isCorrected
        )
    }
}
