import Foundation

/// VoiceOver labels for the keyboard-activatable day and record rows. The rows
/// are native buttons (Tab/arrows focus them, Space/Return activate them), and
/// these labels state what each row is and what activating it does. Badge
/// values describe the stored attribution, never authorship.
public enum RowAccessibility {
    public static func weekDayRowLabel(weekday: String, dayLabel: String, isToday: Bool, count: Int) -> String {
        let countText = count == 0 ? "no records" : "\(count) record\(count == 1 ? "" : "s")"
        let todayText = isToday ? ", today" : ""
        return "\(weekday), \(dayLabel)\(todayText), \(countText). Opens this day in Today."
    }

    public static func recordRowLabel(time: String, summary: String, attribution: String, isCorrected: Bool) -> String {
        let correctionText = isCorrected ? " (your correction)" : ""
        return "Record at \(time): \(summary). Attribution: \(attribution)\(correctionText). Opens the record detail."
    }
}
