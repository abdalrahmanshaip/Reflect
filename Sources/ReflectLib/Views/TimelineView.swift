import SwiftUI

struct TimelineView: View {
    @EnvironmentObject private var store: AppStore

    @State private var filters = TimelineFilterSelection()
    @State private var selected: EvidenceEvent?

    /// Opens pre-filtered to one day (the evidence inspector's complete path).
    init(initialDayKey: String? = nil) {
        _filters = State(initialValue: TimelineFilterSelection(dayKey: initialDayKey))
    }

    var body: some View {
        let projection = store.timelineProjection(dayKey: filters.dayKey, source: filters.source, kind: filters.kind)
        let filteredCount = projection.filteredIndices.count
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("All Records")
                    .font(.headline)
                Text("Observed in files on this Mac. Counts show what was recorded, not effort or skill.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Compact filters so the bar fits narrow windows without pushing
            // the content wider than the window.
            HStack(spacing: 10) {
                Picker("Day", selection: $filters.dayKey) {
                    Text("All days").tag(String?.none)
                    ForEach(store.allDayKeys(), id: \.self) { dayKey in
                        Text(Fmt.sidebarDayLabel(dayKey)).tag(String?.some(dayKey))
                    }
                }
                .labelsHidden()
                .frame(width: 130)
                .accessibilityLabel("Filter by day")
                Picker("Source", selection: $filters.source) {
                    Text("All sources").tag(SourceKind?.none)
                    ForEach(SourceKind.allCases) { kind in
                        Text(kind.displayName).tag(SourceKind?.some(kind))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 150)
                .accessibilityLabel("Filter by source")
                Picker("Type", selection: $filters.kind) {
                    Text("All types").tag(EventKind?.none)
                    ForEach(EventKind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(EventKind?.some(kind))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 130)
                .accessibilityLabel("Filter by record type")
                Spacer()
                Text("\(filteredCount) record\(filteredCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            Divider()

            if projection.filteredIndices.isEmpty {
                let emptyState = TimelineEmptyState.resolve(
                    totalEventCount: store.events.count,
                    matchingEventCount: filteredCount
                ) ?? .emptyStore
                VStack(spacing: 12) {
                    ContentUnavailableCompat(title: emptyState.title, detail: emptyState.detail)
                    if emptyState.offersClearFilters && filters.isActive {
                        Button("Clear filters") {
                            filters.clear()
                        }
                        .accessibilityHint("Show all records by clearing the day, source, and type filters.")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(projection.groups) { group in
                        Section(group.dayKey) {
                            ForEach(group.events(from: store.events)) { event in
                                Button {
                                    selected = event
                                } label: {
                                    EventRow(event: event, attribution: store.effectiveAttribution(for: event))
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                                .reflectClickableHover(RoundedRectangle(cornerRadius: 6))
                                .accessibilityLabel(recordLabel(for: event))
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .background(ReflectPalette.page)
            }
        }
        .sheet(item: $selected) { event in
            EvidenceSheet(event: event)
        }
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
