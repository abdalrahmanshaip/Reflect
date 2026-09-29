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
            + ExclusionTests.entries
            + GitImporterTests.entries
            + AnalysisServiceTests.entries
            + PersistenceTests.entries
            + EventPageTests.entries
            + ReportEditTrackingTests.entries
    }
}

@main
struct ReflectTestRunnerMain {
    static func main() {
        print("Reflect test runner: \(TestRegistry.all.count) tests")
        TestRunner.run(all: TestRegistry.all)
    }
}
