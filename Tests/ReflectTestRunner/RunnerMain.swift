import Foundation
@testable import ReflectLib

/// Central registry of all test suites.
public enum TestRegistry {
    public static var all: [TestEntry] {
        TimestampParserTests.entries
            + CodexImporterTests.entries
            + ClaudeAndCopilotImporterTests.entries
            + DeduplicationTests.entries
            + MissingSourceTests.entries
            + AttributionCorrectionTests.entries
            + InsufficientEvidenceTests.entries
            + ReportGeneratorTests.entries
            + DayOverviewTests.entries
            + LocalDayTests.entries
            + ExclusionTests.entries
            + GitImporterTests.entries
            + AnalysisServiceTests.entries
            + PersistenceTests.entries
            + PersistenceMigrationTests.entries
            + StoreFailureTests.entries
            + StoreVersioningTests.entries
            + SaveOrderTests.entries
            + EventPageTests.entries
            + ReportEditTrackingTests.entries
            + NavigationTests.entries
            + ReflectionDraftTests.entries
            + EvidenceGroupTests.entries
            + ReadingScreenTests.entries
            + SourceControlTests.entries
            + ImportSchedulingTests.entries
            + AnalysisRestoreTests.entries
            + AnalysisPrivacyNoteTests.entries
            + AnalysisStatusHonestyTests.entries
            + AnalysisAgentsTests.entries
            + SettingsDiscoveryTests.entries
            + RowAccessibilityTests.entries
            + DesignPaletteTests.entries
            + HoverAffordanceTests.entries
            + SyntheticPerformanceTests.entries
            + TimelineEmptyStateTests.entries
            + EventProjectionIndexTests.entries
            + RouteProjectionTests.entries
            + SharedContractsTests.entries
            + BoundedContextTests.entries
            + SessionImportTests.entries
            + SessionsStoreTests.entries
            + ContextRetrievalTests.entries
            + ContextPrivacyTests.entries
            + ConversationPersistenceTests.entries
            + ConversationServiceTests.entries
            + RestrictedConversationResponderTests.entries
            + ConversationRuntimeConfigurationTests.entries
    }
}

@main
struct ReflectTestRunnerMain {
    static func main() {
        print("Reflect test runner: \(TestRegistry.all.count) tests")
        let summary = TestRunner.runCollecting(TestRegistry.all)
        _ = SyntheticPerformanceBenchmarks.runAndReport()
        exit(summary.success ? 0 : 1)
    }
}
