import Foundation

enum Fmt {
    private static let englishLocale = Locale(identifier: "en_US_POSIX")

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = englishLocale
        formatter.timeZone = .current
        return formatter
    }()

    private static let sidebarDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        formatter.locale = englishLocale
        formatter.timeZone = .current
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        formatter.locale = englishLocale
        formatter.timeZone = .current
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = englishLocale
        formatter.timeZone = .current
        return formatter
    }()

    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        formatter.locale = englishLocale
        formatter.timeZone = .current
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        formatter.locale = englishLocale
        formatter.timeZone = .current
        return formatter
    }()

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        dayKeyFormatter.string(from: date)
    }

    /// Parses a stored day key back to a local date (start of day).
    static func date(fromDayKey dayKey: String) -> Date? {
        dayKeyFormatter.date(from: dayKey)
    }

    /// Compact sidebar label for a day key, e.g. "Mon 28 Sep".
    static func sidebarDayLabel(_ dayKey: String) -> String {
        guard let date = date(fromDayKey: dayKey) else { return dayKey }
        return sidebarDayFormatter.string(from: date)
    }

    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func dateTime(_ date: Date) -> String {
        dateTimeFormatter.string(from: date)
    }

    static func fullDate(_ date: Date) -> String {
        fullDateFormatter.string(from: date)
    }

    static func weekdayName(for date: Date) -> String {
        weekdayFormatter.string(from: date)
    }

    static func relative(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = englishLocale
        return formatter.localizedString(for: date, relativeTo: now)
    }

    static func usd(_ value: Double) -> String {
        String(format: "$%.4f", value)
    }
}
