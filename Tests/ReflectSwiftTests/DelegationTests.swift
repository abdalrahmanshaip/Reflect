import Testing
import ReflectTestRunner

/// Delegates the full core suite to the explicit test runner.
/// On toolchains where Swift Testing executes normally (e.g. full Xcode), `swift test`
/// therefore runs every Reflect core test. On this machine's Command Line Tools the
/// Swift Testing runner no-ops silently; `swift run reflect-test-runner` is the
/// authoritative local verification command (see README).
struct DelegationTests {
    @Test func fullCoreSuitePasses() {
        let summary = TestRunner.runCollecting(TestRegistry.all, verbose: false)
        #expect(summary.success, "core suite failures: \(summary.failures.joined(separator: " | "))")
    }
}
