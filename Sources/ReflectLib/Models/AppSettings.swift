import Foundation

/// Local application settings. AI analysis is disabled unless the user turns it on explicitly.
public struct AppSettings: Codable, Equatable {
    public var exclusions: [String]
    public var enabledSources: Set<SourceKind>
    public var aiEnabled: Bool
    public var analysisAgent: AnalysisAgentKind?
    public var modelSelections: [AnalysisAgentKind: String]

    // Legacy values remain Codable so existing settings can be read and
    // rewritten without losing unrelated data. The agent workflow never uses
    // these endpoint, pricing, or API-key-era fields.
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
        analysisAgent: AnalysisAgentKind? = nil,
        modelSelections: [AnalysisAgentKind: String] = [:],
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
        self.analysisAgent = analysisAgent
        self.modelSelections = modelSelections
        self.providerEndpoint = providerEndpoint
        self.providerModel = providerModel
        self.pricePerMillionInput = pricePerMillionInput
        self.pricePerMillionOutput = pricePerMillionOutput
        self.usageMode = usageMode
        self.gitRepositoryPath = gitRepositoryPath
        self.maxPreviewCharacters = maxPreviewCharacters
    }

    public static func `default`() -> AppSettings { AppSettings() }

    private enum CodingKeys: String, CodingKey {
        case exclusions
        case enabledSources
        case aiEnabled
        case analysisAgent
        case modelSelections
        case providerEndpoint
        case providerModel
        case pricePerMillionInput
        case pricePerMillionOutput
        case usageMode
        case gitRepositoryPath
        case maxPreviewCharacters
    }

    /// Decodes both the current agent settings and older Reflect settings
    /// files. Missing new keys intentionally mean "no selected agent" rather
    /// than guessing from an old endpoint or model string.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.exclusions = try values.decodeIfPresent([String].self, forKey: .exclusions) ?? []
        self.enabledSources = try values.decodeIfPresent(Set<SourceKind>.self, forKey: .enabledSources)
            ?? Set(SourceKind.allCases)
        self.aiEnabled = try values.decodeIfPresent(Bool.self, forKey: .aiEnabled) ?? false
        self.analysisAgent = try values.decodeIfPresent(AnalysisAgentKind.self, forKey: .analysisAgent)
        self.modelSelections = try values.decodeIfPresent([AnalysisAgentKind: String].self, forKey: .modelSelections) ?? [:]
        self.providerEndpoint = try values.decodeIfPresent(String.self, forKey: .providerEndpoint) ?? ""
        self.providerModel = try values.decodeIfPresent(String.self, forKey: .providerModel) ?? ""
        self.pricePerMillionInput = try values.decodeIfPresent(Double.self, forKey: .pricePerMillionInput) ?? 0
        self.pricePerMillionOutput = try values.decodeIfPresent(Double.self, forKey: .pricePerMillionOutput) ?? 0
        self.usageMode = try values.decodeIfPresent(UsageMode.self, forKey: .usageMode) ?? .estimated
        self.gitRepositoryPath = try values.decodeIfPresent(String.self, forKey: .gitRepositoryPath)
        self.maxPreviewCharacters = try values.decodeIfPresent(Int.self, forKey: .maxPreviewCharacters) ?? 160
    }

    public func model(for agent: AnalysisAgentKind) -> String? {
        modelSelections[agent]
    }

    public mutating func setModel(_ model: String?, for agent: AnalysisAgentKind) {
        let trimmed = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            modelSelections.removeValue(forKey: agent)
        } else {
            modelSelections[agent] = trimmed
        }
    }
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
