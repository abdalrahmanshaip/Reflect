import Foundation

/// Tolerant timestamp parsing for third-party session formats.
enum TimestampParser {
    private static var formatters: [ISO8601DateFormatter] {
        let utc = ISO8601DateFormatter()
        utc.formatOptions = [.withInternetDateTime]
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return [fractional, utc]
    }

    /// Parses ISO-8601 strings (with or without fractional seconds), offsets,
    /// and numeric epoch values in seconds or milliseconds.
    static func parse(_ value: Any?) -> Date? {
        switch value {
        case let text as String:
            return parse(text)
        case let number as NSNumber:
            return parse(number)
        default:
            return nil
        }
    }

    static func parse(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for formatter in formatters {
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        // Some tools log "yyyy-MM-dd HH:mm:ss" in local time.
        let plain = DateFormatter()
        plain.dateFormat = "yyyy-MM-dd HH:mm:ss"
        plain.locale = Locale(identifier: "en_US_POSIX")
        return plain.date(from: trimmed)
    }

    static func parse(_ number: NSNumber) -> Date? {
        let seconds = number.doubleValue
        guard seconds.isFinite, seconds > 0 else { return nil }
        // Heuristic: values above 1e12 are milliseconds.
        if seconds > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: seconds / 1000)
        }
        if seconds > 1_000_000_000 {
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }
}
