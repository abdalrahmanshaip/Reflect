import Foundation
@testable import ReflectLib

struct DayOverviewTests {
    static let suiteName = "DayOverviewTests"
    private let dayKey = "2026-01-05"

    // MARK: Synthetic helpers (never real activity)

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }

    private func event(
        _ id: String,
        at date: Date,
        source: SourceKind,
        kind: EventKind = .userMessage,
        approximate: Bool = false,
        attribution: Attribution = .unclear
    ) -> EvidenceEvent {
        EvidenceEvent(
            id: id,
            sourceKind: source,
            sourceName: source.displayName,
            timestamp: date,
            timestampApproximate: approximate,
            kind: kind,
            summary: "Synthetic \(kind.rawValue) \(id)",
            detail: "",
            evidencePath: "/tmp/reflect-fixture/\(id).jsonl",
            evidenceLine: 1,
            observedAttribution: attribution,
            observedAttributionNote: "Structural role in transcript",
            importedAt: date
        )
    }

    private func answer(_ text: String) -> AnswerEntry {
        AnswerEntry(text: text, updatedAt: date(2026, 1, 5, 19))
    }

    private func correction(_ eventId: String, _ attribution: Attribution) -> AttributionCorrection {
        AttributionCorrection(eventId: eventId, attribution: attribution, updatedAt: date(2026, 1, 5, 20))
    }

    // MARK: Legacy report round-trip

    func legacyReportJSONRoundTripsUnchangedThroughTemporaryStore() throws {
        // Literal JSON in the exact stored schema, including a saved authored answer.
        let legacyJSON = """
        [
          {
            "day" : "2026-01-05",
            "narrative" : "Observed facts for 2026-01-05 (generated draft; edit freely):\\n- 4 events imported from 2 source(s).",
            "narrativeGeneratedAt" : "2026-01-05T18:30:00Z",
            "answers" : {
              "2026-01-05-q1" : {
                "text" : "Synthetic authored answer about a fictional fixture task.",
                "updatedAt" : "2026-01-05T19:00:00Z"
              }
            },
            "analysisResult" : null,
            "analysisGeneratedAt" : null,
            "updatedAt" : "2026-01-05T19:00:00Z"
          }
        ]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([DailyReport].self, from: Data(legacyJSON.utf8))
        try expectEqual(decoded.count, 1)
        let report = try require(decoded.first)
        try expectEqual(report.day, dayKey)
        try expectEqual(
            report.answers["\(dayKey)-q1"]?.text,
            "Synthetic authored answer about a fictional fixture task.",
            "saved answer text must survive decoding untouched"
        )
        try expectTrue(DayOverviewBuilder.isReflected(report), "nonblank saved answer means reflected")

        // Round-trip through a real temporary store.
        let store = PersistenceController(directory: Fixtures.makeTempDirectory("day-overview-legacy"))
        try store.saveReports(decoded)
        let reloaded = try require(try store.loadReports())
        try expectEqual(reloaded, decoded, "reports must round-trip unchanged")

        // Re-encode and decode again: schema and values unchanged.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let reencoded = try decoder.decode([DailyReport].self, from: try encoder.encode(reloaded))
        try expectEqual(reencoded, decoded, "re-encoding must not change stored answers")
    }

    // MARK: Empty day

    func emptyDayReturnsNoEvidenceOverviewWithoutQuestion() throws {
        let overview = DayOverviewBuilder.overview(dayKey: dayKey, events: [], report: nil, corrections: [])

        try expectFalse(overview.hasEvidence)
        try expectEqual(overview.eventCount, 0)
        try expectNil(overview.observedSentence, "no sentence may be invented for an empty day")
        try expectTrue(overview.questions.isEmpty, "no generated question without evidence")
        try expectTrue(overview.facts.isEmpty)
        let note = try require(overview.statusNote, "empty day needs an honest status note")
        try expectTrue(note.lowercased().contains("no evidence"), "note must say no evidence rather than imply a quiet day")
        try expectFalse(overview.reflected)
    }

    // MARK: Sparse day

    func sparseDayBelowThresholdGeneratesNoQuestion() throws {
        let events = [
            event("sp-1", at: date(2026, 1, 5, 9), source: .codex),
            event("sp-2", at: date(2026, 1, 5, 11), source: .claudeCode)
        ]
        let overview = DayOverviewBuilder.overview(dayKey: dayKey, events: events, report: nil, corrections: [])

        try expectTrue(overview.hasEvidence)
        try expectEqual(overview.eventCount, 2)
        let sentence = try require(overview.observedSentence)
        try expectTrue(sentence.contains("2 records"), "sentence must reflect the imported count")
        try expectTrue(overview.questions.isEmpty, "no generated question below the threshold")
        let note = try require(overview.statusNote, "sparse day needs an honest status note")
        try expectTrue(note.contains("at least \(AppConstants.minimumEventsForQuestion)"), "note must state the threshold")
    }

    // MARK: Sufficient day

    func sufficientDayReturnsPrimaryQuestionWithStableIDPlainWordingAndBasis() throws {
        let events = [
            event("sd-1", at: date(2026, 1, 5, 9), source: .codex),
            event("sd-2", at: date(2026, 1, 5, 10), source: .codex),
            event("sd-3", at: date(2026, 1, 5, 14), source: .claudeCode),
            event("sd-4", at: date(2026, 1, 5, 16), source: .claudeCode)
        ]
        let overview = DayOverviewBuilder.overview(dayKey: dayKey, events: events, report: nil, corrections: [correction("sd-1", .you)])

        try expectTrue(overview.questions.isEmpty == false)
        let primary = try require(overview.questions.first, "a sufficient day must have a primary question")
        try expectEqual(primary.id, "\(dayKey)-q1", "primary question keeps the stable existing ID")
        try expectFalse(primary.text.contains(where: \.isNumber), "question wording stays plain; counts belong in the basis")
        let basis = primary.basis
        try expectTrue(basis.contains("4"), "basis must name the record count")
        try expectTrue(basis.contains("Codex CLI") && basis.contains("Claude Code"), "basis must name the sources")
        try expectNil(overview.statusNote, "a sufficient day needs no sparse note")

        let again = DayOverviewBuilder.overview(dayKey: dayKey, events: events, report: nil, corrections: [correction("sd-1", .you)])
        try expectEqual(overview.questions, again.questions, "questions must be deterministic")
        try expectEqual(overview.observedSentence, again.observedSentence, "sentence must be deterministic")
    }

    // MARK: Mixed day

    func mixedDaySeparatesObservedCountsCorrectionsAndCommitMetadata() throws {
        let events = [
            event("mx-1", at: date(2026, 1, 5, 9), source: .codex),
            event("mx-2", at: date(2026, 1, 5, 10, 15), source: .codex),
            event("mx-3", at: date(2026, 1, 5, 11), source: .claudeCode, attribution: .agent),
            event("mx-4", at: date(2026, 1, 5, 13), source: .copilotCLI, approximate: true),
            event("mx-5", at: date(2026, 1, 5, 15), source: .gitLocal, kind: .gitCommit),
            event("mx-6", at: date(2026, 1, 5, 16), source: .gitLocal, kind: .gitCommit)
        ]

        let overview = DayOverviewBuilder.overview(dayKey: dayKey, events: events, report: nil, corrections: [correction("mx-1", .you), correction("mx-2", .you)])

        let sentence = try require(overview.observedSentence)
        try expectTrue(sentence.contains("6 records"), "sentence must count every imported record")
        try expectTrue(sentence.contains("4 sources"), "sentence must count the sources")

        // Observed source facts.
        let observedTexts = overview.facts.filter { $0.marker == .observed }.map(\.text)
        try expectTrue(observedTexts.contains { $0.contains("Codex CLI") && $0.contains("2 records") }, "observed source counts must appear as facts")
        try expectTrue(observedTexts.contains { $0.contains("Copilot CLI") }, "each source appears")
        // Commit metadata stays metadata.
        try expectTrue(observedTexts.contains { $0.contains("2 commits") && $0.lowercased().contains("metadata") && $0.lowercased().contains("authorship is not asserted") }, "commits must be labeled metadata only")
        try expectTrue(observedTexts.contains { $0.contains("approximate timestamp") }, "approximate timestamps must be identified")

        // Corrections are a distinct, separate category.
        let corrections = overview.facts.filter { $0.marker == .correction }
        try expectEqual(corrections.count, 1, "corrections form their own fact")
        try expectTrue(corrections[0].text.contains("You marked 2 records"), "correction fact must attribute the marking to the user")

        // The commit question keeps its stable ID and metadata-only basis.
        try expectTrue(overview.questions.contains { $0.id == "\(dayKey)-q3" && $0.basis.lowercased().contains("metadata") })

        try overviewNeverClaimsAuthorshipOrSkill(in: overview)
    }

    func overviewNeverClaimsAuthorshipOrSkill(in overview: DayOverview) throws {
        var allText = overview.observedSentence ?? ""
        allText += " " + overview.facts.map(\.text).joined(separator: " ")
        allText += " " + overview.questions.map { $0.text + " " + $0.basis }.joined(separator: " ")
        allText += " " + (overview.statusNote ?? "")
        let lowered = allText.lowercased()
        for banned in ["you wrote", "your work shows", "skill", "productivity", "performance"] {
            try expectFalse(lowered.contains(banned), "overview must never claim \(banned); got: \(allText)")
        }
    }

    // Correction facts stay truthful about authorship: only user-attributed
    // corrections are "marked as your own"; other explicit corrections are
    // described without claiming the records are the user's own work.
    func correctionFactsOnlyClaimUserAttributionForYouCorrections() throws {
        let events = [
            event("cf-1", at: date(2026, 1, 5, 9), source: .codex),
            event("cf-2", at: date(2026, 1, 5, 10), source: .codex),
            event("cf-3", at: date(2026, 1, 5, 11), source: .claudeCode),
            event("cf-4", at: date(2026, 1, 5, 12), source: .claudeCode),
            event("cf-5", at: date(2026, 1, 5, 13), source: .copilotCLI),
            event("cf-6", at: date(2026, 1, 5, 14), source: .copilotCLI)
        ]
        let corrections = [
            correction("cf-1", .you),
            correction("cf-2", .you),
            correction("cf-3", .agent),
            correction("cf-4", .unclear)
        ]

        let overview = DayOverviewBuilder.overview(dayKey: dayKey, events: events, report: nil, corrections: corrections)

        let correctionFacts = overview.facts.filter { $0.marker == .correction }.map(\.text)
        try expectEqual(correctionFacts.count, 3, "each distinct attribution value gets its own correction fact")

        // Only the user-attributed corrections say "as your own".
        try expectTrue(correctionFacts.contains { $0.contains("2 records") && $0.lowercased().contains("as your own") },
                       "the two .you corrections are marked as the user's own, got: \(correctionFacts)")
        // Other explicit corrections are described without false authorship.
        try expectTrue(correctionFacts.contains { $0.contains("Agent") && !$0.lowercased().contains("as your own") },
                       "the agent correction must not claim the record is the user's own, got: \(correctionFacts)")
        try expectTrue(correctionFacts.contains { $0.contains("Unclear") && !$0.lowercased().contains("as your own") },
                       "the unclear correction must not claim the record is the user's own, got: \(correctionFacts)")
        // The total correction count must never be claimed as the user's own.
        let joined = correctionFacts.joined(separator: " ")
        try expectFalse(joined.contains("You marked 4"),
                        "must not claim all 4 corrections mark records as the user's own")
        // Corrections stay a separate category from observed values.
        let observedFacts = overview.facts.filter { $0.marker == .observed }
        try expectFalse(observedFacts.isEmpty, "observed facts remain present")
        for observed in observedFacts {
            try expectFalse(observed.text.lowercased().contains("your correction"),
                            "observed facts must not absorb correction content")
        }

        try overviewNeverClaimsAuthorshipOrSkill(in: overview)
    }

    // MARK: Recent days

    func recentDaysIncludeReportOnlyDaysAndReflectOnlyAuthoredAnswers() throws {
        let events = [
            event("rd-1", at: date(2026, 1, 5, 9), source: .codex),
            event("rd-2", at: date(2026, 1, 5, 10), source: .codex),
            event("rd-3", at: date(2026, 1, 5, 11), source: .codex),
            event("rd-4", at: date(2026, 1, 5, 12), source: .codex),
            event("rd-5", at: date(2026, 1, 4, 9), source: .claudeCode),
            event("rd-6", at: date(2026, 1, 4, 10), source: .claudeCode)
        ]
        let reflectedReport = DailyReport(
            day: "2026-01-05",
            narrative: "Generated draft narrative — never counts as reflection.",
            narrativeGeneratedAt: date(2026, 1, 5, 18),
            answers: ["\(dayKey)-q1": answer("Synthetic authored answer.")],
            analysisResult: nil,
            analysisGeneratedAt: nil,
            updatedAt: date(2026, 1, 5, 19)
        )
        let blankAnswerReport = DailyReport(
            day: "2026-01-03",
            narrative: "",
            narrativeGeneratedAt: nil,
            answers: ["2026-01-03-q1": answer("   ")],
            analysisResult: nil,
            analysisGeneratedAt: nil,
            updatedAt: date(2026, 1, 3, 19)
        )
        let narrativeOnlyReport = DailyReport(
            day: "2026-01-02",
            narrative: "Generated draft narrative with no user answers.",
            narrativeGeneratedAt: date(2026, 1, 2, 18),
            answers: [:],
            analysisResult: nil,
            analysisGeneratedAt: nil,
            updatedAt: date(2026, 1, 2, 19)
        )

        let recent = DayOverviewBuilder.recentDays(events: events, reports: [reflectedReport, blankAnswerReport, narrativeOnlyReport])
        let byDay = Dictionary(uniqueKeysWithValues: recent.map { ($0.dayKey, $0) })

        // Report-only days (2026-01-03, 2026-01-02) must appear alongside event days.
        try expectEqual(Set(byDay.keys), Set(["2026-01-05", "2026-01-04", "2026-01-03", "2026-01-02"]))
        try expectEqual(recent.map(\.dayKey), recent.map(\.dayKey).sorted(by: >), "newest day first")

        let day5 = try require(byDay["2026-01-05"])
        try expectEqual(day5.eventCount, 4)
        try expectTrue(day5.reflected, "a nonblank saved answer marks the day reflected")
        try expectEqual(day5.statusLabel, "Reflected")

        let day4 = try require(byDay["2026-01-04"])
        try expectEqual(day4.eventCount, 2)
        try expectFalse(day4.reflected)
        try expectEqual(day4.statusLabel, "Not yet")

        let day3 = try require(byDay["2026-01-03"])
        try expectEqual(day3.eventCount, 0)
        try expectTrue(day3.hasReport, "report-only day is included")
        try expectFalse(day3.reflected, "whitespace-only answers never count as reflection")
        try expectEqual(day3.statusLabel, "No records")

        let day2 = try require(byDay["2026-01-02"])
        try expectFalse(day2.reflected, "a generated narrative draft never counts as user reflection")
        try expectEqual(day2.statusLabel, "No records")

        let limited = DayOverviewBuilder.recentDays(events: events, reports: [reflectedReport], limit: 2)
        try expectEqual(limited.count, 2)
        try expectEqual(limited.map(\.dayKey), ["2026-01-05", "2026-01-04"])

        try expectFalse(DayOverviewBuilder.isReflected(nil), "no report means not reflected")
    }

    // MARK: DayOverview from a stored report

    func overviewCarriesReportPresenceAndReflectionFromStoredReport() throws {
        let events = [
            event("ov-1", at: date(2026, 1, 5, 9), source: .codex),
            event("ov-2", at: date(2026, 1, 5, 10), source: .codex),
            event("ov-3", at: date(2026, 1, 5, 11), source: .codex)
        ]
        let report = DailyReport(
            day: dayKey,
            narrative: "Generated draft.",
            narrativeGeneratedAt: date(2026, 1, 5, 18),
            answers: [:],
            analysisResult: nil,
            analysisGeneratedAt: nil,
            updatedAt: date(2026, 1, 5, 18)
        )

        let draftOnly = DayOverviewBuilder.overview(dayKey: dayKey, events: events, report: report, corrections: [])
        try expectTrue(draftOnly.hasReport)
        try expectFalse(draftOnly.reflected, "generated narrative alone is not reflection")

        var authored = report
        authored.answers["\(dayKey)-q1"] = answer("Synthetic authored reflection.")
        let reflected = DayOverviewBuilder.overview(dayKey: dayKey, events: events, report: authored, corrections: [])
        try expectTrue(reflected.reflected)

        let noReport = DayOverviewBuilder.overview(dayKey: dayKey, events: events, report: nil, corrections: [])
        try expectFalse(noReport.hasReport)
    }

    static var entries: [TestEntry] {
        let tests = DayOverviewTests()
        return [
            TestEntry(suite: suiteName, name: "legacyReportJSONRoundTripsUnchangedThroughTemporaryStore") { try tests.legacyReportJSONRoundTripsUnchangedThroughTemporaryStore() },
            TestEntry(suite: suiteName, name: "emptyDayReturnsNoEvidenceOverviewWithoutQuestion") { try tests.emptyDayReturnsNoEvidenceOverviewWithoutQuestion() },
            TestEntry(suite: suiteName, name: "sparseDayBelowThresholdGeneratesNoQuestion") { try tests.sparseDayBelowThresholdGeneratesNoQuestion() },
            TestEntry(suite: suiteName, name: "sufficientDayReturnsPrimaryQuestionWithStableIDPlainWordingAndBasis") { try tests.sufficientDayReturnsPrimaryQuestionWithStableIDPlainWordingAndBasis() },
            TestEntry(suite: suiteName, name: "mixedDaySeparatesObservedCountsCorrectionsAndCommitMetadata") { try tests.mixedDaySeparatesObservedCountsCorrectionsAndCommitMetadata() },
            TestEntry(suite: suiteName, name: "correctionFactsOnlyClaimUserAttributionForYouCorrections") { try tests.correctionFactsOnlyClaimUserAttributionForYouCorrections() },
            TestEntry(suite: suiteName, name: "recentDaysIncludeReportOnlyDaysAndReflectOnlyAuthoredAnswers") { try tests.recentDaysIncludeReportOnlyDaysAndReflectOnlyAuthoredAnswers() },
            TestEntry(suite: suiteName, name: "overviewCarriesReportPresenceAndReflectionFromStoredReport") { try tests.overviewCarriesReportPresenceAndReflectionFromStoredReport() }
        ]
    }
}
