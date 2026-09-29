import Foundation

enum ReportEditTracking {
    static func narrativeChanged(current: String, saved: String) -> Bool {
        current != saved
    }
}
