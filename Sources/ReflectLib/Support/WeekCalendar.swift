import Foundation

/// Shared week math for the This Week screen, kept out of SwiftUI so the
/// day-key round trip stays testable.
public enum WeekCalendar {
    /// The seven local days of the week containing `date`, in order.
    public static func days(inWeekOf date: Date, calendar: Calendar = .current) -> [Date] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    /// "Sep 28 – Oct 4" style label for the week containing `date`.
    public static func weekLabel(for date: Date, calendar: Calendar = .current) -> String {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        let end = interval.end.addingTimeInterval(-1)
        return "\(formatter.string(from: interval.start)) – \(formatter.string(from: end))"
    }
}
