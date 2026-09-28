import Foundation

/// Local application settings. AI analysis is disabled unless the user turns it on explicitly.
public struct AppSettings: Codable, Equatable {
    public var exclusions: [String]
    public var enabledSources: Set<SourceKind>
    public var aiEnabled: Bool
    public var providerEndpoint: String
    public var providerModel: String
    public var pricePerMillionInput: Double
    public var pricePerMillionOutput: Double
    public var usageMode: UsageMode
    public var gitRepositoryPath: String?
    public var maxPreviewCharacters: Int

    public init(
        exclusions: [String] = [],
        enabledSources: Set<SourceKind> = Set(SourceKind.allCases),
        aiEnabled: Bool = false,
        providerEndpoint: String = "",
        providerModel: String = "",
        pricePerMillionInput: Double = 0,
        pricePerMillionOutput: Double = 0,
        usageMode: UsageMode = .estimated,
        gitRepositoryPath: String? = nil,
        maxPreviewCharacters: Int = 160
    ) {
        self.exclusions = exclusions
        self.enabledSources = enabledSources
        self.aiEnabled = aiEnabled
        self.providerEndpoint = providerEndpoint
        self.providerModel = providerModel
        self.pricePerMillionInput = pricePerMillionInput
        self.pricePerMillionOutput = pricePerMillionOutput
        self.usageMode = usageMode
        self.gitRepositoryPath = gitRepositoryPath
        self.maxPreviewCharacters = maxPreviewCharacters
    }

    public static func `default`() -> AppSettings { AppSettings() }
}

/// Whether cost estimates use a rough local estimate or the usage the provider reports back.
public enum UsageMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case estimated
    case requested

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .estimated: return "Estimated (rough local estimate)"
        case .requested: return "Requested (usage reported by provider)"
        }
    }
}
