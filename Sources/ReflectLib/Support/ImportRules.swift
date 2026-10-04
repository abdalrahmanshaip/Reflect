import Foundation

/// Single source of truth for when an import may start. Imports are always
/// explicit user actions; the rules keep unverified, missing, disabled, and
/// unselected sources from being importable, so the UI can never present them
/// as imported.
public enum ImportRules {
    /// The context an import request comes from. Bulk scheduling additionally
    /// requires detected availability, so "Import all available sources" never
    /// scans or reads a source that is not actually present.
    public enum SchedulingScope: Equatable {
        case singleSource
        case bulkImport
    }

    /// The one eligibility decision, applied before any import work is
    /// scheduled. A source must not already be importing, must be enabled,
    /// and must be format-verified; Git additionally needs an explicitly
    /// selected repository. Bulk scheduling also requires detected
    /// availability (`.detected`, or `.manual` for Git's user-selected
    /// repository). A single-source import may still run a missing source so
    /// it can report "not detected" honestly, but a disabled or unverified
    /// source is rejected before anything is scheduled.
    public static func isImportEligible(
        kind: SourceKind,
        scope: SchedulingScope,
        importing: Set<SourceKind>,
        enabledSources: Set<SourceKind>,
        gitRepositoryPath: String?,
        formatVerified: Bool,
        availability: SourceAvailability?
    ) -> Bool {
        guard !importing.contains(kind) else { return false }
        guard enabledSources.contains(kind) else { return false }
        guard formatVerified else { return false }
        if kind == .gitLocal {
            guard !(gitRepositoryPath ?? "").isEmpty else { return false }
            if scope == .bulkImport {
                return availability?.status == .manual
            }
            return true
        }
        if scope == .bulkImport {
            switch availability?.status {
            case .detected: return true
            case .manual, .detectedUnverified, .missing, nil: return false
            }
        }
        return true
    }

    /// Whether the Sources Import button may offer this source right now.
    /// Single-source semantics: a missing source stays offerable so the
    /// explicit action can report "not detected" honestly.
    public static func isImportAllowed(
        kind: SourceKind,
        importing: Set<SourceKind>,
        enabledSources: Set<SourceKind>,
        gitRepositoryPath: String?,
        formatVerified: Bool
    ) -> Bool {
        isImportEligible(
            kind: kind,
            scope: .singleSource,
            importing: importing,
            enabledSources: enabledSources,
            gitRepositoryPath: gitRepositoryPath,
            formatVerified: formatVerified,
            availability: nil
        )
    }
}
