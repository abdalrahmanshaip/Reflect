import Foundation
@testable import ReflectLib

/// Deterministic, synthetic data used only by the performance runner. The
/// fixture deliberately spans local days so route projections exercise the
/// same calendar boundaries as the app without reading a real store.
struct SyntheticPerformanceFixture {
    /// The generated day and source cycles repeat together every least-common
    /// multiple of 30 days and 4 sources, so each source/day file can assign
    /// stable one-based line numbers from the global fixture index.
    private static let recordsPerSourceDayIdentityCycle = 60

    let anchor: Date
    let events: [EvidenceEvent]
    let reports: [DailyReport]
    let corrections: [AttributionCorrection]

    static func make(count: Int, anchor: Date = Fixtures.referenceDate) -> Self {
        let calendar = Calendar.current
        let sources: [SourceKind] = [.codex, .claudeCode, .copilotCLI, .gitLocal]
        let kinds: [EventKind] = [.userMessage, .agentMessage, .toolCall, .toolOutput, .gitCommit]
        let start = calendar.startOfDay(for: anchor)
        let events = (0..<count).map { index in
            let dayOffset = -(index % 30)
            let day = calendar.date(byAdding: .day, value: dayOffset, to: start)!
            let timestamp = calendar.date(byAdding: .minute, value: 8 * 60 + (index % 720), to: day)!
            let source = sources[index % sources.count]
            return EvidenceEvent(
                id: "synthetic-performance-\(index)",
                sourceKind: source,
                sourceName: source.displayName,
                timestamp: timestamp,
                timestampApproximate: index % 19 == 0,
                kind: kinds[index % kinds.count],
                summary: "Synthetic performance record \(index)",
                detail: "",
                evidencePath: "/tmp/reflect-performance-fixture/\(source.rawValue)/day-\(index % 30).jsonl",
                evidenceLine: index / Self.recordsPerSourceDayIdentityCycle + 1,
                observedAttribution: index % 3 == 0 ? .agent : .unclear,
                observedAttributionNote: "Synthetic structural role",
                importedAt: anchor
            )
        }

        let reportOffsets = [-31, -17, -4, -1]
        let reports = reportOffsets.map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: start)!
            let dayKey = Fmt.dayKey(day)
            let answer = offset == -1
                ? ["(dayKey)-q1": AnswerEntry(text: "Synthetic authored performance note.", updatedAt: anchor)]
                : [:]
            return DailyReport(
                day: dayKey,
                narrative: offset == -17 ? "Synthetic generated draft." : "",
                narrativeGeneratedAt: offset == -17 ? anchor : nil,
                answers: answer,
                analysisResult: nil,
                analysisGeneratedAt: nil,
                updatedAt: anchor
            )
        }

        let corrections: [AttributionCorrection] = events.enumerated().compactMap { (index, event) in
            guard index % 97 == 0 else { return nil }
            return AttributionCorrection(eventId: event.id, attribution: .you, updatedAt: anchor)
        }
        return Self(anchor: anchor, events: events, reports: reports, corrections: corrections)
    }

    static func identityValidationFailure(for events: [EvidenceEvent]) -> String? {
        struct EvidenceLocator: Hashable {
            let source: SourceKind
            let path: String
            let line: Int
        }

        var ids = Set<String>()
        var locators = Set<EvidenceLocator>()
        for event in events {
            guard !event.id.isEmpty, ids.insert(event.id).inserted else {
                return "record IDs must be non-empty and unique"
            }
            guard !event.evidencePath.isEmpty, let line = event.evidenceLine else {
                return "each record needs a path and line evidence locator"
            }
            let locator = EvidenceLocator(source: event.sourceKind, path: event.evidencePath, line: line)
            guard locators.insert(locator).inserted else {
                return "source/path/line evidence locators must be unique"
            }
        }
        return nil
    }
}

struct SyntheticAllRecordsProjection {
    let filtered: [EvidenceEvent]
    let groups: [(dayKey: String, events: [EvidenceEvent])]

    static func baseline(
        events: [EvidenceEvent],
        dayKey: String? = nil,
        source: SourceKind? = nil,
        kind: EventKind? = nil
    ) -> Self {
        let filtered = events.filter { event in
            (dayKey == nil || Fmt.dayKey(event.timestamp) == dayKey)
                && (source == nil || event.sourceKind == source)
                && (kind == nil || event.kind == kind)
        }
        let groups = Dictionary(grouping: filtered) { Fmt.dayKey($0.timestamp) }
            .map { (dayKey: $0.key, events: $0.value.sorted { $0.timestamp > $1.timestamp }) }
            .sorted { $0.dayKey > $1.dayKey }
        return Self(filtered: filtered, groups: groups)
    }
}

struct SyntheticPerformanceTests {
    static let suiteName = "SyntheticPerformanceTests"

    func fixtureScalesAreDeterministicAndMultiDay() throws {
        let first = SyntheticPerformanceFixture.make(count: 2_000)
        let second = SyntheticPerformanceFixture.make(count: 2_000)
        try expectEqual(first.events, second.events, "the same count must produce byte-equivalent synthetic events")
        try expectEqual(Set(first.events.map { Fmt.dayKey($0.timestamp) }).count, 30, "fixture spans 30 local days")
        try expectEqual(Set(first.events.map(\.id)).count, first.events.count, "each synthetic event ID must be unique")
        try expectTrue(Set(first.events.map(\.evidencePath)).count > 1, "synthetic evidence paths must vary across source/day files")
        let evidenceLocators = first.events.map {
            "\($0.sourceKind.rawValue)|\($0.evidencePath)|\(String(describing: $0.evidenceLine))"
        }
        try expectEqual(Set(evidenceLocators).count, first.events.count, "each synthetic source/path/line locator must be unique")
        try expectEqual(first.reports.count, 4, "fixture includes report-only and reflected states")
        try expectTrue(first.corrections.allSatisfy { $0.eventId.hasPrefix("synthetic-performance-") }, "corrections stay synthetic")
    }

    func benchmarkIdentityValidationRejectsDuplicates() throws {
        let event = SyntheticPerformanceFixture.make(count: 1).events[0]
        let duplicateID = EvidenceEvent(
            id: event.id,
            sourceKind: event.sourceKind,
            sourceName: event.sourceName,
            timestamp: event.timestamp.addingTimeInterval(1),
            timestampApproximate: event.timestampApproximate,
            kind: event.kind,
            summary: "Distinct synthetic record with a duplicate ID",
            detail: event.detail,
            evidencePath: event.evidencePath + "/different-session.jsonl",
            evidenceLine: 1,
            observedAttribution: event.observedAttribution,
            observedAttributionNote: event.observedAttributionNote,
            importedAt: event.importedAt
        )
        let duplicateLocator = EvidenceEvent(
            id: event.id + "-distinct-id",
            sourceKind: event.sourceKind,
            sourceName: event.sourceName,
            timestamp: event.timestamp.addingTimeInterval(2),
            timestampApproximate: event.timestampApproximate,
            kind: event.kind,
            summary: "Distinct synthetic record with a duplicate locator",
            detail: event.detail,
            evidencePath: event.evidencePath,
            evidenceLine: event.evidenceLine,
            observedAttribution: event.observedAttribution,
            observedAttributionNote: event.observedAttributionNote,
            importedAt: event.importedAt
        )

        try expectTrue(
            SyntheticPerformanceFixture.identityValidationFailure(for: [event, duplicateID]) != nil,
            "duplicate record IDs must reject benchmark input even with different evidence locators"
        )
        try expectTrue(
            SyntheticPerformanceFixture.identityValidationFailure(for: [event, duplicateLocator]) != nil,
            "duplicate source/path/line locators must reject benchmark input even with different record IDs"
        )
    }

    func routeProjectionReferenceProducesExpectedShapes() throws {
        let fixture = SyntheticPerformanceFixture.make(count: 21)
        let weekly = GrowthAnalyzer.weekTallies(events: fixture.events, endingAt: fixture.anchor, calendar: .current, weekCount: 8)
        let recent = DayOverviewBuilder.recentDays(events: fixture.events, reports: fixture.reports, limit: 8)
        let todayKey = Fmt.dayKey(fixture.anchor)
        let todayEvents = fixture.events.filter { Fmt.dayKey($0.timestamp) == todayKey }
        let overview = DayOverviewBuilder.overview(
            dayKey: todayKey,
            events: todayEvents,
            report: fixture.reports.first { $0.day == todayKey },
            corrections: fixture.corrections.filter { correction in todayEvents.contains { $0.id == correction.eventId } }
        )
        let allRecords = SyntheticAllRecordsProjection.baseline(events: fixture.events)

        try expectEqual(fixture.events.count, 21)
        try expectEqual(weekly.count, 8)
        try expectTrue(recent.count >= 4, "events and report-only days are both represented")
        try expectEqual(overview.eventCount, todayEvents.count)
        try expectEqual(allRecords.filtered.count, 21)
        try expectEqual(allRecords.groups.reduce(0) { $0 + $1.events.count }, 21)
    }

    static var entries: [TestEntry] {
        let tests = SyntheticPerformanceTests()
        return [
            TestEntry(suite: suiteName, name: "fixtureScalesAreDeterministicAndMultiDay") {
                try tests.fixtureScalesAreDeterministicAndMultiDay()
            },
            TestEntry(suite: suiteName, name: "benchmarkIdentityValidationRejectsDuplicates") {
                try tests.benchmarkIdentityValidationRejectsDuplicates()
            },
            TestEntry(suite: suiteName, name: "routeProjectionReferenceProducesExpectedShapes") {
                try tests.routeProjectionReferenceProducesExpectedShapes()
            }
        ]
    }
}

struct SyntheticBenchmarkPoint: CustomStringConvertible {
    let projection: String
    let eventCount: Int
    let iterations: Int
    let warmups: Int
    let p50Milliseconds: Double
    let p95Milliseconds: Double
    let checksum: Int

    var description: String {
        let paddedProjection = projection.padding(toLength: 22, withPad: " ", startingAt: 0)
        return "\(paddedProjection) \(eventCount)  runs=\(iterations)  p50=\(String(format: "%9.3f", p50Milliseconds)) ms  p95=\(String(format: "%9.3f", p95Milliseconds)) ms  checksum=\(checksum)"
    }
}

enum SyntheticPerformanceBenchmarks {
    static let counts = [21, 2_000, 10_000]
    static let warmupCount = 4
    static let iterationCount = 24

    @discardableResult
    static func runAndReport() -> [SyntheticBenchmarkPoint] {
        let fixtures = counts.map { SyntheticPerformanceFixture.make(count: $0) }
        for fixture in fixtures {
            guard let failure = SyntheticPerformanceFixture.identityValidationFailure(for: fixture.events) else { continue }
            preconditionFailure("Synthetic benchmark identities are invalid for \(fixture.events.count) events: \(failure)")
        }
        let points = fixtures.flatMap(measure)
        print("SYNTHETIC_BENCHMARK: counts=21,2000,10000 warmups=\(warmupCount) iterations=\(iterationCount) storage=temporary/in-memory-secret")
        for point in points { print("BENCHMARK \(point)") }
        writeReport(points)
        return points
    }

    private static func measure(_ fixture: SyntheticPerformanceFixture) -> [SyntheticBenchmarkPoint] {
        let calendar = Calendar.current
        let index = EventProjectionIndex(events: fixture.events, calendar: calendar)
        let todayKey = Fmt.dayKey(fixture.anchor)
        let todayEvents = index.events(onDay: todayKey, from: fixture.events)
        let corrections = fixture.corrections.filter { correction in todayEvents.contains { $0.id == correction.eventId } }

        return [
            timed("index build", eventCount: fixture.events.count) {
                EventProjectionIndex(events: fixture.events, calendar: calendar).dayKeys.count
            },
            timed("This Week route projection", eventCount: fixture.events.count) {
                RouteProjectionBuilder.weekly(referenceDate: fixture.anchor, events: fixture.events, index: index).total
            },
            timed("Patterns aggregation", eventCount: fixture.events.count) {
                let summary = GrowthAnalyzer.summarize(events: fixture.events, corrections: fixture.corrections, today: fixture.anchor, calendar: calendar, index: index)
                return summary.observations.count &+ summary.weekly.reduce(0) { $0 &+ $1.eventCount }
            },
            timed("recent-day summaries", eventCount: fixture.events.count) {
                DayOverviewBuilder.recentDays(index: index, reports: fixture.reports, limit: 9)
                    .reduce(0) { $0 &+ $1.eventCount }
            },
            timed("Today route projection", eventCount: fixture.events.count) {
                let projection = RouteProjectionBuilder.today(
                    dayKey: todayKey,
                    events: todayEvents,
                    report: fixture.reports.first { $0.day == todayKey },
                    corrections: corrections
                )
                return projection.overview.eventCount
                    &+ projection.overview.facts.count
                    &+ projection.overview.questions.count
                    &+ projection.sessions.reduce(0) { $0 &+ $1.events.count }
                    &+ projection.hourLanes.reduce(0) { $0 &+ $1.marks.count }
            },
            timed("All Records route projection", eventCount: fixture.events.count) {
                let projection = RouteProjectionBuilder.timeline(
                    events: fixture.events,
                    index: index,
                    dayKey: nil,
                    source: nil,
                    kind: nil
                )
                return projection.filteredIndices.count
                    &+ projection.groups.reduce(0) { $0 &+ $1.indices.count }
            }
        ]
    }

    private static func timed(_ projection: String, eventCount: Int, _ operation: () -> Int) -> SyntheticBenchmarkPoint {
        for _ in 0..<warmupCount { _ = operation() }
        var samples: [Double] = []
        samples.reserveCapacity(iterationCount)
        var checksum = 0
        for _ in 0..<iterationCount {
            let start = DispatchTime.now().uptimeNanoseconds
            checksum &+= operation()
            let elapsed = DispatchTime.now().uptimeNanoseconds - start
            samples.append(Double(elapsed) / 1_000_000.0)
        }
        let sorted = samples.sorted()
        let p50 = percentile(sorted, fraction: 0.50)
        let p95 = percentile(sorted, fraction: 0.95)
        return SyntheticBenchmarkPoint(
            projection: projection,
            eventCount: eventCount,
            iterations: iterationCount,
            warmups: warmupCount,
            p50Milliseconds: p50,
            p95Milliseconds: p95,
            checksum: checksum
        )
    }

    private static func percentile(_ sorted: [Double], fraction: Double) -> Double {
        guard let last = sorted.indices.last else { return 0 }
        let index = min(last, max(0, Int(ceil(Double(sorted.count) * fraction)) - 1))
        return sorted[index]
    }

    private static func writeReport(_ points: [SyntheticBenchmarkPoint]) {
        let env = ProcessInfo.processInfo.environment
        let root = URL(fileURLWithPath: env["REFLECT_PERFORMANCE_EVIDENCE_ROOT"] ?? ".supergoal/optimize-reflect-macos-performance-and-e-3TAaMc/evidence", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let mode = env["REFLECT_PERFORMANCE_MODE"] ?? "latest"
        let name = mode == "baseline" ? "performance-baseline.md" : "performance-latest.md"
        let path = root.appendingPathComponent(name)
        var text = """
        # Reflect synthetic performance \(mode)

        - Fixture: deterministic synthetic events only; no real store, history, Keychain, network, or provider access.
        - Storage: temporary/in-memory fixture configuration.
        - Build invocation: reflect-test-runner (configuration supplied by the caller).
        - Projection path: \(mode == "baseline" ? "pre-index route reference" : "ephemeral EventProjectionIndex for day/week consumers; index build is measured separately").
        - Route path: \(mode == "baseline" ? "baseline view derivations" : "single route snapshot for Today, This Week, and All Records filter/group branches").
        - Warmups: \(warmupCount)
        - Timed iterations: \(iterationCount)
        - Calendar: current local calendar; anchor: \(Fixtures.referenceDate.timeIntervalSince1970)
        - Measurement: monotonic wall-clock projection timing; p50 and p95 in milliseconds.
        - Limits: `/usr/bin/sample` is stack sampling, not a SwiftUI frame/Hangs trace; Xcode Instruments/xctrace is unavailable in this environment.

        | Projection | Events | Warmups | Iterations | p50 (ms) | p95 (ms) |
        | --- | ---: | ---: | ---: | ---: | ---: |

        """
        for point in points {
            text += "| \(point.projection) | \(point.eventCount) | \(point.warmups) | \(point.iterations) | \(String(format: "%.3f", point.p50Milliseconds)) | \(String(format: "%.3f", point.p95Milliseconds)) |\n"
        }
        try? text.write(to: path, atomically: true, encoding: .utf8)
        print("BENCHMARK_REPORT: \(path.path)")
    }
}
