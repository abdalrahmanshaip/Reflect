import Foundation
@testable import ReflectLib

/// In-memory secrets for runner tests — never touches the Keychain.
final class MemorySecretStore: SecretStore {
    private var values: [String: String] = [:]
    func secret(account: String) -> String? { values[account] }
    func setSecret(_ value: String, account: String) throws { values[account] = value }
    func deleteSecret(account: String) throws { values.removeValue(forKey: account) }
}

struct SourceControlTests {
    static let suiteName = "SourceControlTests"

    // Unverified formats (Cursor, VS Code) can never be imported, even when
    // detected and enabled.
    func unverifiedSourcesCannotBeImported() throws {
        for kind in [SourceKind.cursor, .vscode] {
            try expectFalse(kind.formatVerified, "\(kind.displayName) format is unverified")
            try expectFalse(ImportRules.isImportAllowed(
                kind: kind,
                importing: [],
                enabledSources: Set(SourceKind.allCases),
                gitRepositoryPath: nil,
                formatVerified: kind.formatVerified
            ), "\(kind.displayName) must not be importable while its format is unverified")
        }
        for kind in [SourceKind.codex, .claudeCode, .copilotCLI] {
            try expectTrue(kind.formatVerified, "\(kind.displayName) format is fixture-verified")
        }
    }

    // Missing and disabled sources stay unimportable; git needs a chosen repo.
    func disabledMissingAndUnselectedSourcesCannotImport() throws {
        let onlyCodex: Set<SourceKind> = [.codex]
        try expectTrue(ImportRules.isImportAllowed(
            kind: .codex, importing: [], enabledSources: onlyCodex,
            gitRepositoryPath: nil, formatVerified: true
        ))
        try expectFalse(ImportRules.isImportAllowed(
            kind: .claudeCode, importing: [], enabledSources: onlyCodex,
            gitRepositoryPath: nil, formatVerified: true
        ), "a source the user disabled cannot import")
        try expectFalse(ImportRules.isImportAllowed(
            kind: .codex, importing: [.codex], enabledSources: onlyCodex,
            gitRepositoryPath: nil, formatVerified: true
        ), "an in-flight import cannot be started again")
        try expectFalse(ImportRules.isImportAllowed(
            kind: .gitLocal, importing: [], enabledSources: Set(SourceKind.allCases),
            gitRepositoryPath: nil, formatVerified: true
        ), "git without a chosen repository cannot import")
        try expectTrue(ImportRules.isImportAllowed(
            kind: .gitLocal, importing: [], enabledSources: Set(SourceKind.allCases),
            gitRepositoryPath: "/tmp/reflect-fixture/repo", formatVerified: true
        ), "git with a chosen repository can import")
    }

    // Merely creating the store (opening Sources or Settings) starts no import,
    // imports no events, and performs no provider/Keychain side effects.
    @MainActor
    func openingStoreStartsNoImportAndNoProviderCalls() throws {
        let directory = Fixtures.makeTempDirectory("source-controls")
        let store = AppStore(
            persistence: PersistenceController(directory: directory),
            secrets: MemorySecretStore(),
            home: Fixtures.makeTempDirectory("source-controls-home")
        )
        try expectTrue(store.importing.isEmpty, "no import may run on its own")
        try expectNil(store.lastImportSummary, "no import summary may appear on its own")
        try expectTrue(store.events.isEmpty, "availability scanning must never import events")
        try expectFalse(store.hasStoredAPIKey, "no Keychain key exists in a fresh store")
        try expectTrue(store.aiStatus().isDisabledDefault, "AI stays disabled by default")
    }

    static var entries: [TestEntry] {
        let tests = SourceControlTests()
        return [
            TestEntry(suite: suiteName, name: "unverifiedSourcesCannotBeImported") { try tests.unverifiedSourcesCannotBeImported() },
            TestEntry(suite: suiteName, name: "disabledMissingAndUnselectedSourcesCannotImport") { try tests.disabledMissingAndUnselectedSourcesCannotImport() },
            TestEntry(suite: suiteName, name: "openingStoreStartsNoImportAndNoProviderCalls") { try MainActor.assumeIsolated { try tests.openingStoreStartsNoImportAndNoProviderCalls() } }
        ]
    }
}

extension AnalysisService.Status {
    var isDisabledDefault: Bool {
        if case .disabled = self { return true }
        return false
    }
}
