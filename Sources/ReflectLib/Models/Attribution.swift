import Foundation

/// Structural attribution recorded at import time. Never asserted as human authorship.
public enum Attribution: String, Codable, CaseIterable, Identifiable, Hashable {
    case you
    case agent
    case unclear

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .you: return "You"
        case .agent: return "Agent"
        case .unclear: return "Unclear"
        }
    }
}

/// Provenance labels shown in the UI so observed facts, app inference, and user input stay distinct.
public enum EvidenceLabel: String, Codable, CaseIterable, Hashable {
    case observed
    case inference
    case correction

    public var displayName: String {
        switch self {
        case .observed: return "Observed"
        case .inference: return "App-generated inference"
        case .correction: return "Your correction"
        }
    }
}
