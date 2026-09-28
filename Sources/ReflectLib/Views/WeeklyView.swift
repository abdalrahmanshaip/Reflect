import SwiftUI

struct WeeklyView: View {
    @EnvironmentObject private var store: AppStore

    @State private var weekOffset = 0
    @State private var selectedDay: Date?

    private var referenceDate: Date {
        Calendar.current.date(byAdding: .weekOfYear, value: weekOffset, to: Date()) ?? Date()
    }

    private var weekInterval: DateInterval? {
        Calendar.current.dateInterval(of: .weekOfYear, for: referenceDate)
    }

    private var weekDays: [Date] {
        guard let interval = weekInterval else { return [] }
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private func events(on date: Date) -> [EvidenceEvent] {
        let key = Fmt.dayKey(date)
        return store.events.filter { Fmt.dayKey($0.timestamp) == key }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    weekOffset -= 1
                } label: {
                    Image(systemName: "chevron.left")
                }
                Text(weekLabel)
                    .font(.headline)
                Button {
                    weekOffset += 1
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(weekOffset >= 0)
                Spacer()
                Text(summaryLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Days in this week", systemImage: "calendar.day.timeline.left")
                            .font(.headline)
                        ForEach(weekDays, id: \.timeIntervalSince1970) { day in
                            let dayEvents = events(on: day)
                            DayRow(
                                date: day,
                                count: dayEvents.count,
                                isToday: Fmt.dayKey(day) == Fmt.dayKey(Date()),
                                isSelected: selectedDay.map { Fmt.dayKey($0) == Fmt.dayKey(day) } ?? false
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { selectedDay = day }
                        }
                    }

                    if let selectedDay {
                        let dayEvents = events(on: selectedDay).sorted { $0.timestamp < $1.timestamp }
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Evidence for \(Fmt.dayKey(selectedDay))", systemImage: "doc.text.magnifyingglass")
                                .font(.headline)
                            if dayEvents.isEmpty {
                                Text("No evidence for this day.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(dayEvents) { event in
                                    EventRow(event: event, attribution: store.effectiveAttribution(for: event))
                                }
                            }
                        }
                    }

                    Text("This view lists observed evidence only. Growth readings and their limitations are shown in the Growth tab; no score is produced anywhere in Reflect.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
        }
    }

    private var weekLabel: String {
        guard let interval = weekInterval else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: interval.start)) – \(formatter.string(from: interval.end.addingTimeInterval(-1)))"
    }

    private var summaryLine: String {
        let total = weekDays.reduce(0) { $0 + events(on: $1).count }
        let daysWithEvidence = weekDays.filter { !events(on: $0).isEmpty }.count
        let missing = 7 - daysWithEvidence
        return "\(total) event(s) · \(daysWithEvidence) day(s) with evidence · \(missing) day(s) without"
    }
}

private struct DayRow: View {
    let date: Date
    let count: Int
    let isToday: Bool
    let isSelected: Bool

    var body: some View {
        HStack {
            Text(weekdayName)
                .frame(width: 90, alignment: .leading)
            Text(Fmt.dayKey(date))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if isToday {
                Text("today")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
            Spacer()
            if count == 0 {
                Text("No evidence")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(count) event(s)")
                    .font(.callout.monospacedDigit())
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var weekdayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }
}
