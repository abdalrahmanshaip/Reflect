import SwiftUI
@testable import ReflectLib
import AppKit

// Test-only synthetic UI launcher (never shipped, never pointed at real data).
//
// Privacy contract: the store directory and the fake HOME both live in a fresh
// temporary directory (or the directory named by REFLECT_FIXTURE_DIR), secrets
// are held in memory only, and every event/report below is synthetic fixture
// content. It reads nothing from the user's real histories and never touches
// the Keychain. The only file written outside the fixture directory is the PNG
// named by REFLECT_FIXTURE_SCREENSHOT, an explicit operator direction.
//
// Environment switches (all optional):
//   REFLECT_FIXTURE_DIR        persistent fixture store/home directory
//   REFLECT_FIXTURE_SCENARIO   "populated" (default), "empty", or "damaged-store"
//   REFLECT_FIXTURE_WIDTH/HEIGHT  window size in points
//   REFLECT_FIXTURE_DARK=1     dark appearance
//   REFLECT_FIXTURE_AGENT=codex|claude_code  preselect a synthetic settings agent
//   REFLECT_FIXTURE_DISCOVERY_DELAY=<seconds>  synthetic slow agent discovery:
//       the fake availability provider sleeps off the main actor before
//       reporting the same synthetic statuses. It never launches a real or
//       fake CLI process; the delay is a pure Task sleep, so Settings stays
//       responsive and cancellable while "discovery" is pending.
//   REFLECT_FIXTURE_SCREENSHOT=<png path>  capture the main window once at launch
//   REFLECT_FIXTURE_QUIT=1     exit after the screenshot

final class FixtureSecretStore: SecretStore {
    private var values: [String: String] = [:]
    func secret(account: String) -> String? { values[account] }
    func setSecret(_ value: String, account: String) throws { values[account] = value }
    func deleteSecret(account: String) throws { values.removeValue(forKey: account) }
}

private enum FixtureDays {
    /// Local day key for a day relative to today (same format as the app's store).
    static func dayKey(_ offset: Int, today: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let start = Calendar.current.startOfDay(for: today)
        let day = Calendar.current.date(byAdding: .day, value: offset, to: start)!
        return formatter.string(from: day)
    }
}

enum FixtureEnvironment {
    static func resolveDirectories() -> (store: URL, home: URL) {
        let env = ProcessInfo.processInfo.environment
        let base: URL
        if let configured = env["REFLECT_FIXTURE_DIR"] {
            base = URL(fileURLWithPath: configured, isDirectory: true)
        } else {
            base = FileManager.default.temporaryDirectory
                .appendingPathComponent("reflect-ui-fixture-\(UUID().uuidString)", isDirectory: true)
        }
        let store = base.appendingPathComponent("Store", isDirectory: true)
        let home = base.appendingPathComponent("Home", isDirectory: true)
        try? FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return (store, home)
    }

    static func event(
        _ id: String, dayOffset: Int, hour: Int, minute: Int, source: SourceKind,
        kind: EventKind, approximate: Bool = false, today: Date
    ) -> EvidenceEvent {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: today)
        let timestamp = calendar.date(byAdding: DateComponents(day: dayOffset, hour: hour, minute: minute), to: start)!
        // One transcript file per source and day so session groups read like
        // real sessions; git commits share the fixture repository path.
        let evidencePath = source == .gitLocal
            ? "/tmp/reflect-fixture/fixture-repo"
            : "/tmp/reflect-fixture/fixture-\(source.rawValue)-day\(-dayOffset).jsonl"
        return EvidenceEvent(
            id: id,
            sourceKind: source,
            sourceName: source.displayName,
            timestamp: timestamp,
            timestampApproximate: approximate,
            kind: kind,
            summary: "Synthetic \(kind.rawValue) \(id) about a fictional fixture task",
            detail: "",
            evidencePath: evidencePath,
            evidenceLine: 1,
            observedAttribution: id.hasSuffix("-u") ? .you : .unclear,
            observedAttributionNote: "Structural role in transcript",
            importedAt: today
        )
    }

    /// A week of clearly synthetic activity. Content never mirrors a real history.
    static func syntheticEvents(today: Date, count: Int = 21) -> [EvidenceEvent] {
        let base: [EvidenceEvent] = [
            event("fx-1-u", dayOffset: -1, hour: 9, minute: 5, source: .codex, kind: .userMessage, today: today),
            event("fx-2", dayOffset: -1, hour: 9, minute: 20, source: .codex, kind: .agentMessage, today: today),
            event("fx-3-u", dayOffset: -1, hour: 10, minute: 2, source: .claudeCode, kind: .userMessage, today: today),
            event("fx-4", dayOffset: -1, hour: 10, minute: 30, source: .claudeCode, kind: .toolCall, today: today),
            event("fx-5", dayOffset: -1, hour: 11, minute: 12, source: .codex, kind: .agentMessage, today: today),
            event("fx-6-u", dayOffset: -2, hour: 8, minute: 40, source: .copilotCLI, kind: .userMessage, approximate: true, today: today),
            event("fx-7", dayOffset: -2, hour: 9, minute: 5, source: .copilotCLI, kind: .agentMessage, approximate: true, today: today),
            event("fx-8-u", dayOffset: -2, hour: 15, minute: 0, source: .claudeCode, kind: .userMessage, today: today),
            event("fx-9", dayOffset: -2, hour: 15, minute: 25, source: .claudeCode, kind: .agentMessage, today: today),
            event("fx-10-u", dayOffset: -4, hour: 9, minute: 0, source: .codex, kind: .userMessage, today: today),
            event("fx-11", dayOffset: -4, hour: 9, minute: 45, source: .codex, kind: .toolOutput, today: today),
            event("fx-12", dayOffset: -4, hour: 13, minute: 10, source: .claudeCode, kind: .agentMessage, today: today),
            event("fx-13", dayOffset: -4, hour: 14, minute: 0, source: .gitLocal, kind: .gitCommit, today: today),
            event("fx-14", dayOffset: -4, hour: 16, minute: 35, source: .gitLocal, kind: .gitCommit, today: today),
            event("fx-15-u", dayOffset: -5, hour: 10, minute: 0, source: .claudeCode, kind: .userMessage, today: today),
            event("fx-16", dayOffset: -5, hour: 10, minute: 30, source: .claudeCode, kind: .agentMessage, today: today),
            event("fx-17-u", dayOffset: -6, hour: 11, minute: 0, source: .codex, kind: .userMessage, today: today),
            event("fx-18", dayOffset: -6, hour: 11, minute: 20, source: .codex, kind: .agentMessage, today: today),
            event("fx-19", dayOffset: -6, hour: 12, minute: 5, source: .copilotCLI, kind: .toolCall, today: today),
            event("fx-20", dayOffset: -6, hour: 14, minute: 40, source: .claudeCode, kind: .agentMessage, today: today),
            event("fx-21", dayOffset: -6, hour: 16, minute: 15, source: .gitLocal, kind: .gitCommit, today: today)
        ]
        guard count > base.count else { return Array(base.prefix(max(0, count))) }

        let sources: [SourceKind] = [.codex, .claudeCode, .copilotCLI, .gitLocal]
        let kinds: [EventKind] = [.userMessage, .agentMessage, .toolCall, .toolOutput, .gitCommit]
        var expanded = base
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: today)
        for index in base.count..<count {
            let dayOffset = -(index % 30)
            let day = calendar.date(byAdding: .day, value: dayOffset, to: start)!
            let timestamp = calendar.date(byAdding: .minute, value: 8 * 60 + (index % 720), to: day)!
            let source = sources[index % sources.count]
            let kind = kinds[index % kinds.count]
            expanded.append(EvidenceEvent(
                id: "fx-scale-\(index)",
                sourceKind: source,
                sourceName: source.displayName,
                timestamp: timestamp,
                timestampApproximate: index % 19 == 0,
                kind: kind,
                summary: "Synthetic \(kind.rawValue) fx-scale-\(index) about a fictional fixture task",
                detail: "",
                evidencePath: "/tmp/reflect-fixture/scale-day-\(index % 30).jsonl",
                evidenceLine: index + 1,
                observedAttribution: index % 3 == 0 ? .agent : .unclear,
                observedAttributionNote: "Structural role in synthetic fixture",
                importedAt: today
            ))
        }
        return expanded
    }

    /// Reports matching the sidebar states: reflected, generated-only, report-only,
    /// and untouched days. Only nonblank authored answers mark a day reflected.
    static func syntheticReports(today: Date) -> [DailyReport] {
        let calendar = Calendar.current
        func dayKey(_ offset: Int) -> String {
            FixtureDays.dayKey(offset, today: today)
        }
        func report(_ offset: Int, answers: [String: AnswerEntry] = [:], narrative: String = "") -> DailyReport {
            DailyReport(
                day: dayKey(offset),
                narrative: narrative,
                narrativeGeneratedAt: narrative.isEmpty ? nil : calendar.date(byAdding: .hour, value: 18, to: calendar.startOfDay(for: today)),
                answers: answers,
                analysisResult: nil,
                analysisGeneratedAt: nil,
                updatedAt: today
            )
        }
        return [
            report(-1, answers: ["\(dayKey(-1))-q1": AnswerEntry(
                text: "Synthetic authored reflection: the fixture export task took longest; next time I would batch the fixture writes.",
                updatedAt: today
            )]),
            report(-2, narrative: "Generated draft for fixture day -2. Never counted as user reflection."),
            report(-3, answers: ["\(dayKey(-3))-q1": AnswerEntry(text: "   ", updatedAt: today)]),
            report(-4, answers: ["\(dayKey(-4))-q1": AnswerEntry(
                text: "Synthetic authored reflection: two fixture commits landed after the fixture review.",
                updatedAt: today
            )])
        ]
    }

    @MainActor
    static func makeStore() -> (store: AppStore, fixtureRoot: URL) {
        let directories = resolveDirectories()
        let scenario = ProcessInfo.processInfo.environment["REFLECT_FIXTURE_SCENARIO"] ?? "populated"
        let eventCount = max(0, Int(ProcessInfo.processInfo.environment["REFLECT_FIXTURE_EVENT_COUNT"] ?? "21") ?? 21)
        let today = Date()

        let persistence = PersistenceController(directory: directories.store)
        if scenario == "populated" {
            try? persistence.saveEvents(syntheticEvents(today: today, count: eventCount))
            try? persistence.saveReports(syntheticReports(today: today))
        }
        if scenario == "damaged-store" {
            // Synthetic damaged-store fixture: malformed events bytes so the
            // app renders its storage recovery surface. Never real user data.
            let damaged = directories.store.appendingPathComponent("events.json")
            try? Data("{\"events\": [ {\"synthetic-damaged-fixture\":".utf8).write(to: damaged)
        }
        if scenario == "obstructed-store" {
            // Synthetic obstructed-store runtime scenario: one durable
            // synthetic revision is seeded while the store is writable, then
            // the directory is made unwritable after load. The save attempt
            // below must fail visibly and publish nothing that is not on
            // disk. Temporary fixture data only.
            let durable = syntheticReports(today: today).prefix(1)
            try? persistence.saveReports(Array(durable))
        }
        if let selectedAgent = ProcessInfo.processInfo.environment["REFLECT_FIXTURE_AGENT"] {
            var fixtureSettings = AppSettings()
            fixtureSettings.analysisAgent = AnalysisAgentKind(rawValue: selectedAgent)
            try? persistence.saveSettings(fixtureSettings)
        }
        let syntheticAgentStatuses = AnalysisAgentKind.supported.map { kind in
            AnalysisAgentStatus(
                kind: kind,
                executableURL: URL(fileURLWithPath: "/tmp/reflect-ui-fixture/\(kind.executableName)"),
                availability: .ready
            )
        }
        // Default: synthetic statuses, immediate. With an explicit delay the
        // fake provider sleeps off the main actor first — a controllable fake
        // discovery with no subprocess involved at all.
        let discoveryDelay: TimeInterval?
        if let raw = ProcessInfo.processInfo.environment["REFLECT_FIXTURE_DISCOVERY_DELAY"] {
            discoveryDelay = TimeInterval(raw)
        } else {
            discoveryDelay = nil
        }
        let analysisAvailabilityProvider: @Sendable () async -> [AnalysisAgentStatus] = {
            if let discoveryDelay {
                try? await Task.sleep(nanoseconds: UInt64(discoveryDelay * 1_000_000_000))
            }
            return syntheticAgentStatuses
        }
        let store = AppStore(
            persistence: persistence,
            secrets: FixtureSecretStore(),
            home: directories.home,
            analysisAvailabilityProvider: analysisAvailabilityProvider
        )
        if scenario == "obstructed-store" {
            // The store loaded from durable bytes; now the directory turns
            // unwritable and a user-style report save runs. The staged write
            // must reject it, surface the error, and leave the published
            // reports at the durable revision.
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o555],
                ofItemAtPath: directories.store.path
            )
            let todayKey = FixtureDays.dayKey(0, today: today)
            var draft = DailyReport(
                day: todayKey,
                narrative: "",
                narrativeGeneratedAt: nil,
                answers: [:],
                analysisResult: nil,
                analysisGeneratedAt: nil,
                updatedAt: today
            )
            draft.answers[ReflectionDraftModel.noteAnswerID(for: todayKey)] = AnswerEntry(
                text: "Synthetic obstructed-run draft that must not publish.",
                updatedAt: today
            )
            _ = store.saveReport(draft)
            // Evidence-only: the exact user-facing error text, for offline
            // privacy checks. Never part of the shipped app.
            if let errorReportPath = ProcessInfo.processInfo.environment["REFLECT_FIXTURE_ERROR_REPORT"] {
                let text = store.lastError.map { "\($0)\n" } ?? "no error surfaced\n"
                try? text.write(toFile: errorReportPath, atomically: true, encoding: .utf8)
            }
        }
        return (store, directories.store.deletingLastPathComponent())
    }

    /// Parses REFLECT_FIXTURE_ROUTE into an initial sidebar route so captures can
    /// show a specific selection without scripted clicks.
    @MainActor
    static func initialRoute(today: Date) -> ReflectRoute? {
        let value = ProcessInfo.processInfo.environment["REFLECT_FIXTURE_ROUTE"] ?? ""
        if value == "week" { return .week }
        if value == "patterns" { return .patterns }
        if value == "records" { return .allRecords(dayKey: nil) }
        if value == "sources" { return .sources }
        if value == "settings" { return .settings }
        if value.hasPrefix("day:") {
            let offset = Int(value.dropFirst("day:".count)) ?? 0
            return .day(dayKey: FixtureDays.dayKey(offset, today: today))
        }
        return nil
    }

    @MainActor
    static func showsTodayEvidence() -> Bool {
        ProcessInfo.processInfo.environment["REFLECT_FIXTURE_EVIDENCE"] == "1"
    }

    @MainActor
    static func showsTodayAnalysis() -> Bool {
        ProcessInfo.processInfo.environment["REFLECT_FIXTURE_ANALYSIS"] == "1"
    }

    @MainActor
    static func expandsLocalData() -> Bool {
        ProcessInfo.processInfo.environment["REFLECT_FIXTURE_LOCAL_DATA"] == "1"
    }

    static func todayEvidenceTab() -> TodayEvidenceInspector.Tab {
        ProcessInfo.processInfo.environment["REFLECT_FIXTURE_EVIDENCE_TAB"] == "hours" ? .byHour : .sessions
    }
}

final class FixtureAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        let env = ProcessInfo.processInfo.environment
        if env["REFLECT_FIXTURE_DARK"] == "1" {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        if env["REFLECT_FIXTURE_LIGHT"] == "1" {
            NSApp.appearance = NSAppearance(named: .aqua)
        }
        guard let shotPath = env["REFLECT_FIXTURE_SCREENSHOT"] else { return }
        let quitAfter = env["REFLECT_FIXTURE_QUIT"] == "1"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            if let reportPath = env["REFLECT_FIXTURE_WINDOW_REPORT"] {
                Self.writeWindowReport(to: URL(fileURLWithPath: reportPath))
            }
            Self.captureWindow(to: URL(fileURLWithPath: shotPath))
            if quitAfter { NSApp.terminate(nil) }
        }
    }

    /// Writes the visible-window list plus the app-menu Settings entry for
    /// capture debugging (fixture only).
    static func writeWindowReport(to url: URL) {
        var lines = NSApp.windows.compactMap { window -> String? in
            guard window.isVisible else { return nil }
            let frame = window.frame
            return "\(window.title) | id=\(window.identifier?.rawValue ?? "-") | frame=\(Int(frame.width))x\(Int(frame.height)) | number=\(window.windowNumber)"
        }
        if let appMenu = NSApp.mainMenu {
            for item in appMenu.items {
                for entry in item.submenu?.items ?? [] where entry.title.contains("Settings") {
                    lines.append("menu: \(item.title) → \(entry.title) | enabled=\(entry.isEnabled) | key=\(entry.keyEquivalent)")
                }
            }
        }
        let env = ProcessInfo.processInfo.environment
        lines.append("fixture: scenario=\(env["REFLECT_FIXTURE_SCENARIO"] ?? "populated") eventCount=\(env["REFLECT_FIXTURE_EVENT_COUNT"] ?? "21") route=\(env["REFLECT_FIXTURE_ROUTE"] ?? "today") discoveryDelay=\(env["REFLECT_FIXTURE_DISCOVERY_DELAY"] ?? "none") storage=temporary secretStore=in-memory")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// Captures the fixture window to PNG. Prefers the window image; falls back
    /// to caching the content view when window capture is unavailable. Any
    /// additional visible window (for example a presented alert) is captured
    /// to a suffixed path so dialogs are part of the evidence.
    static func captureWindow(to url: URL) {
        // Sheets come last: the main window keeps the primary capture path,
        // and an attached alert sheet is captured as an extra evidence window.
        let visible = NSApp.windows
            .filter { $0.isVisible }
            .sorted { ($0.isSheet ? 1 : 0) < ($1.isSheet ? 1 : 0) }
        for (index, window) in visible.enumerated() {
            let windowURL = index == 0
                ? url
                : url.deletingLastPathComponent().appendingPathComponent(
                    "\(url.deletingPathExtension().lastPathComponent)-window\(index).\(url.pathExtension)")
            let windowID = CGWindowID(window.windowNumber)
            if let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.bestResolution]) {
                let rep = NSBitmapImageRep(cgImage: cgImage)
                if let data = rep.representation(using: .png, properties: [:]) {
                    try? data.write(to: windowURL)
                    continue
                }
            }
            guard let contentView = window.contentView,
                  let rep = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else { continue }
            contentView.cacheDisplay(in: contentView.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: windowURL)
            }
        }
    }
}

@main
struct ReflectUIFixtureApp: App {
    @NSApplicationDelegateAdaptor(FixtureAppDelegate.self) private var appDelegate
    @StateObject private var store: AppStore
    private let windowWidth: Double
    private let windowHeight: Double
    private let initialRoute: ReflectRoute?
    private let showsTodayEvidence: Bool
    private let todayEvidenceTab: TodayEvidenceInspector.Tab
    private let showsTodayAnalysis: Bool
    private let expandsLocalData: Bool

    init() {
        let made = FixtureEnvironment.makeStore()
        _store = StateObject(wrappedValue: made.store)
        let env = ProcessInfo.processInfo.environment
        windowWidth = Double(env["REFLECT_FIXTURE_WIDTH"] ?? "") ?? 1280
        windowHeight = Double(env["REFLECT_FIXTURE_HEIGHT"] ?? "") ?? 800
        initialRoute = FixtureEnvironment.initialRoute(today: Date())
        showsTodayEvidence = FixtureEnvironment.showsTodayEvidence()
        todayEvidenceTab = FixtureEnvironment.todayEvidenceTab()
        showsTodayAnalysis = FixtureEnvironment.showsTodayAnalysis()
        expandsLocalData = FixtureEnvironment.expandsLocalData()
    }

    var body: some Scene {
        WindowGroup("Reflect — Synthetic Fixture") {
            ContentView(
                initialRoute: initialRoute,
                showsTodayEvidence: showsTodayEvidence,
                todayEvidenceTab: todayEvidenceTab,
                showsTodayAnalysis: showsTodayAnalysis,
                expandsLocalData: expandsLocalData
            )
            .environmentObject(store)
            .frame(minWidth: 620, minHeight: 520)
            .frame(width: windowWidth, height: windowHeight)
        }
        // Native Settings scene mirrors the shipped app so the fixture can
        // exercise the system Settings menu and Command-comma against the
        // same synthetic store.
        Settings {
            SettingsView()
                .environmentObject(store)
                .frame(minWidth: 620, minHeight: 460)
        }
        // Captures must be true to the requested point size: the window hugs
        // the fixed content frame instead of the system default.
        .windowResizability(.contentSize)
    }
}
