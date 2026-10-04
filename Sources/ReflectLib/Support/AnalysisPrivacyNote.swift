import Foundation

/// Truthful privacy wording for the day's optional analysis surface. The old
/// unconditional "Nothing from this day has left this Mac" claim becomes false
/// once an explicit run sends selected records to the agent's service (or once a day
/// with a previously attached result is reopened), so the line derives from the
/// actual send state. Records are only ever sent through the explicit
/// selection + Run flow.
public enum AnalysisPrivacyNote {
    public enum SendState: Equatable {
        /// There is no attached result in storage; a previous unattached run
        /// cannot be ruled out after the in-memory analysis model is recreated.
        case noAttachedResult
        /// A run is in flight: records are being sent right now.
        case inFlight
        /// Records were sent: either a finished run this session or a previously
        /// attached stored result.
        case sent
        /// The last attempt failed, so whether records reached the agent service is unknown.
        case attemptFailed
    }

    public static func text(aiEnabled: Bool, state: SendState) -> String {
        let availability = "AI analysis is optional and \(aiEnabled ? "available" : "turned off")."
        let settingsHint = "Configure it in Settings."
        switch state {
        case .noAttachedResult:
            return "\(availability) No saved analysis result is attached for this day. Selected records are sent to the agent's service only when you explicitly run analysis. \(settingsHint)"
        case .inFlight:
            return "\(availability) Your selected records for this day are being sent to the agent's service for analysis right now. \(settingsHint)"
        case .sent:
            return "\(availability) Selected records from this day were sent to the agent's service when you ran the analysis. \(settingsHint)"
        case .attemptFailed:
            return "\(availability) The last analysis attempt did not complete, so whether records reached the provider is unknown. \(settingsHint)"
        }
    }

    /// Derives the truthful send state for a day from storage and the session's
    /// analysis run state, so the parent privacy line can subscribe directly to
    /// the model's published transitions. A running request is being sent now;
    /// a finished run or a stored attached result means records were sent; a
    /// failed attempt or a canceled run is an incomplete attempt whose
    /// transmission outcome is unknown — the request may already have
    /// transmitted some or all records — except where a stored attached result
    /// independently proves an earlier send; and a restored result also proves
    /// an earlier run sent records.
    static func sendState(
        hasStoredAnalysis: Bool,
        runState: OptionalAnalysisModel.RunState?
    ) -> SendState {
        if runState == .running { return .inFlight }
        if case .restored = runState { return .sent }
        var sentThisSession = false
        if case .finished = runState { sentThisSession = true }
        if hasStoredAnalysis || sentThisSession { return .sent }
        if case .failed = runState { return .attemptFailed }
        if case .cancelled = runState { return .attemptFailed }
        return .noAttachedResult
    }
}
