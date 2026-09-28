import Foundation

// A minimal, dependency-free test harness.
// Rationale: this machine has Command Line Tools only. The CLT ships Swift Testing,
// but its SwiftPM integration silently no-ops (`swift test` reports success without
// running any test). This runner makes test results explicit and exits non-zero on failure.

public struct TestFailure: Error, CustomStringConvertible {
    public let message: String
    public var description: String { message }

    public init(_ message: String) {
        self.message = message
    }
}

public func expectTrue(_ condition: Bool, _ message: String = "condition was false", file: StaticString = #filePath, line: UInt = #line) throws {
    guard condition else {
        throw TestFailure("\(file):\(line): expected true — \(message)")
    }
}

public func expectFalse(_ condition: Bool, _ message: String = "condition was true", file: StaticString = #filePath, line: UInt = #line) throws {
    try expectTrue(!condition, message, file: file, line: line)
}

public func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) throws {
    guard actual == expected else {
        throw TestFailure("\(file):\(line): expected \(expected), got \(actual) \(message)")
    }
}

public func expectNotEqual<T: Equatable>(_ actual: T, _ unexpected: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) throws {
    guard actual != unexpected else {
        throw TestFailure("\(file):\(line): value unexpectedly equals \(unexpected) \(message)")
    }
}

public func expectNil<T>(_ value: T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) throws {
    guard value == nil else {
        throw TestFailure("\(file):\(line): expected nil, got \(String(describing: value)) \(message)")
    }
}

public func require<T>(_ value: T?, _ message: String = "unexpected nil", file: StaticString = #filePath, line: UInt = #line) throws -> T {
    guard let value else {
        throw TestFailure("\(file):\(line): \(message)")
    }
    return value
}

public struct TestEntry {
    public let suite: String
    public let name: String
    public let run: () throws -> Void

    public init(suite: String, name: String, run: @escaping () throws -> Void) {
        self.suite = suite
        self.name = name
        self.run = run
    }
}

public struct TestRunSummary {
    public let passed: Int
    public let failures: [String]
    public var success: Bool { failures.isEmpty }
}

public enum TestRunner {
    /// Runs every test, printing results. Returns a summary instead of exiting.
    public static func runCollecting(_ entries: [TestEntry], verbose: Bool = true) -> TestRunSummary {
        var passed = 0
        var failures: [String] = []
        for entry in entries {
            do {
                try entry.run()
                passed += 1
                if verbose {
                    print("PASS  \(entry.suite).\(entry.name)")
                }
            } catch {
                failures.append("\(entry.suite).\(entry.name): \(error)")
                print("FAIL  \(entry.suite).\(entry.name) — \(error)")
            }
        }
        print("--------------------------------------------------")
        print("\(passed) passed, \(failures.count) failed, \(passed + failures.count) total")
        if !failures.isEmpty {
            print("\nFailed tests:")
            failures.forEach { print("  - \($0)") }
        }
        return TestRunSummary(passed: passed, failures: failures)
    }

    public static func run(all entries: [TestEntry]) -> Never {
        let summary = runCollecting(entries)
        exit(summary.success ? 0 : 1)
    }
}
