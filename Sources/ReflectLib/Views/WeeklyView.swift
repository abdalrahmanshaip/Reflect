import SwiftUI

/// Design A "This Week": observed day rows for the selected week. Choosing a
/// day navigates to that exact date in Today; the view itself never edits
/// stored reports.
struct WeeklyView: View {
    @EnvironmentObject private var store: AppStore
    var onOpenDay: (String) -> Void = { _ in }

    @State private var weekOffset = 0

    private var referenceDate: Date {
        Calendar.current.date(byAdding: .weekOfYear, value: weekOffset, to: Date()) ?? Date()
    }

    var body: some View {
        let projection = store.weeklyProjection(referenceDate: referenceDate)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    Button {
                        weekOffset -= 1
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 26, height: 22)
                    }
                    .accessibilityLabel("Previous week")
                    .reflectClickableHover(RoundedRectangle(cornerRadius: 5))
                    Divider()
                        .frame(height: 14)
                    Button {
                        weekOffset += 1
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 26, height: 22)
                            .foregroundStyle(weekOffset >= 0 ? Color(nsColor: .disabledControlTextColor) : Color(nsColor: .controlTextColor))
                    }
                    .disabled(weekOffset >= 0)
                    .accessibilityLabel("Next week")
                    .reflectClickableHover(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .background(Capsule().fill(ReflectPalette.button))
                .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.5))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Previous or next week")

                VStack(alignment: .leading, spacing: 1) {
                    Text("This Week")
                        .font(.headline)
                    Text(WeekCalendar.weekLabel(for: referenceDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(summaryLine(for: projection))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 8) {
                        ObservedMark()
                        Text("Days in this week")
                            .font(.callout.weight(.semibold))
                        Text("choose a day to open it in Today")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(projection.days.enumerated()), id: \.element.timeIntervalSince1970) { index, day in
                            Button {
                                onOpenDay(Fmt.dayKey(day))
                            } label: {
                                WeekDayRow(
                                    date: day,
                                    count: projection.counts[index],
                                    isToday: Fmt.dayKey(day) == Fmt.dayKey(Date())
                                )
                            }
                            .buttonStyle(.plain)
                            .reflectClickableHover(RoundedRectangle(cornerRadius: 6))
                            .accessibilityLabel(RowAccessibility.weekDayRowLabel(
                                weekday: Fmt.weekdayName(for: day),
                                dayLabel: Fmt.sidebarDayLabel(Fmt.dayKey(day)),
                                isToday: Fmt.dayKey(day) == Fmt.dayKey(Date()),
                                count: projection.counts[index]
                            ))
                        }
                    }

                    Text("This view lists observed records only. Counts show what was imported, not effort or skill — a day without records is unknown, not idle.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 48)
                .padding(.top, 30)
                .padding(.bottom, 44)
                .frame(maxWidth: 700, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func summaryLine(for projection: WeeklyRouteProjection) -> String {
        let total = projection.total
        let daysWithRecords = projection.daysWithRecords
        let without = 7 - daysWithRecords
        return "\(total) record\(total == 1 ? "" : "s") · \(daysWithRecords) day\(daysWithRecords == 1 ? "" : "s") with records · \(without) without"
    }
}

private struct WeekDayRow: View {
    let date: Date
    let count: Int
    let isToday: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(Fmt.weekdayName(for: date))
                .frame(width: 96, alignment: .leading)
            Text(Fmt.sidebarDayLabel(Fmt.dayKey(date)))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            if isToday {
                Text("Today")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(ReflectPalette.accent)
            }
            Spacer()
            if count == 0 {
                Text("No records")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(count) record\(count == 1 ? "" : "s")")
                    .font(.callout.monospacedDigit())
            }
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
