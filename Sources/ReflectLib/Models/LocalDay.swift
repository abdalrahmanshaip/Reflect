import Foundation

/// A civil day identified by calendar identifier, time zone identifier, and
/// year/month/day. Identity and equality include every field: the same instant
/// can belong to different civil days under different time zones, and a
/// persisted day's identity must never silently move when the machine's time
/// zone changes.
///
/// Construction from an instant is deterministic: callers supply the Calendar
/// and TimeZone explicitly; the machine's implicit current time zone is never
/// used for persisted identity.
public struct LocalDay: Equatable, Hashable, Codable {
    public let calendarIdentifier: String
    public let timeZoneIdentifier: String
    public let year: Int
    public let month: Int
    public let day: Int

    /// Direct construction with an explicit, fully-specified identity.
    public init(
        calendarIdentifier: String,
        timeZoneIdentifier: String,
        year: Int,
        month: Int,
        day: Int
    ) {
        self.calendarIdentifier = calendarIdentifier
        self.timeZoneIdentifier = timeZoneIdentifier
        self.year = year
        self.month = month
        self.day = day
    }

    /// Deterministic construction: decomposes `instant` into civil Y/M/D using
    /// exactly the supplied calendar and time zone, recording both identifiers
    /// as part of the identity.
    public init(instant: Date, calendar: Calendar, timeZone: TimeZone) {
        var calendar = calendar
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: instant)
        guard
            let year = components.year,
            let month = components.month,
            let day = components.day
        else {
            preconditionFailure(
                "LocalDay: calendar \(String(describing: calendar.identifier)) failed to decompose instant \(instant)"
            )
        }
        self.calendarIdentifier = String(describing: calendar.identifier)
        self.timeZoneIdentifier = timeZone.identifier
        self.year = year
        self.month = month
        self.day = day
    }
}
