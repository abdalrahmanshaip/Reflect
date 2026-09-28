import SwiftUI

struct TimelineView: View {
    @EnvironmentObject private var store: AppStore

    @State private var sourceFilter: SourceKind?
    @State private var kindFilter: EventKind?
    @State private var selected: EvidenceEvent?

    private var filtered: [EvidenceEvent] {
        store.events.filter { event in
            (sourceFilter == nil || event.sourceKind == sourceFilter)
                && (kindFilter == nil || event.kind == kindFilter)
        }
    }

    private var groups: [(dayKey: String, events: [EvidenceEvent])] {
        let grouped = Dictionary(grouping: filtered) { Fmt.dayKey($0.timestamp) }
        return grouped
            .map { (dayKey: $0.key, events: $0.value.sorted { $0.timestamp > $1.timestamp }) }
            .sorted { $0.dayKey > $1.dayKey }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Source", selection: $sourceFilter) {
                    Text("All sources").tag(SourceKind?.none)
                    ForEach(SourceKind.allCases) { kind in
                        Text(kind.displayName).tag(SourceKind?.some(kind))
                    }
                }
                .frame(width: 240)
                Picker("Type", selection: $kindFilter) {
                    Text("All types").tag(EventKind?.none)
                    ForEach(EventKind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(EventKind?.some(kind))
                    }
                }
                .frame(width: 200)
                Spacer()
                Text("\(filtered.count) event(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if filtered.isEmpty {
                ContentUnavailableCompat(
                    title: "No events yet",
                    detail: "Imports run only when you start them in Sources. Repeated imports are deduplicated."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groups, id: \.dayKey) { group in
                        Section(group.dayKey) {
                            ForEach(group.events) { event in
                                EventRow(event: event, attribution: store.effectiveAttribution(for: event))
                                    .contentShape(Rectangle())
                                    .onTapGesture { selected = event }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(item: $selected) { event in
            EvidenceSheet(event: event)
        }
    }
}

struct ContentUnavailableCompat: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
    }
}
