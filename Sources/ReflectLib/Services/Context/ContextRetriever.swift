import Foundation

/// Why retrieval failed. Retrieval fails closed: a damaged, unreadable, or
/// migration-locked store never produces an envelope that could masquerade
/// as a complete view of history. Messages are safe English — they name the
/// store only, never payload bytes, transcript content, or paths.
public enum ContextRetrievalFailure: Error, Equatable {
    case storeDamaged(store: StoreName, message: String)
}

/// Deterministic, transparent, bounded retrieval over Reflect's own
/// persisted stores, per the M2 context slice.
///
/// Boundaries:
/// - The retriever reads only the versioned stores owned by
///   `PersistenceController` (sessions, events, corrections, reports). It
///   receives no source URLs, never scans history folders, never re-reads
///   source files, never touches credentials, and never invokes a provider.
/// - Selection is term/recency based with no embeddings and no network
///   dependency. Ordering is fully deterministic: relevance, recency, then
///   stable ID tie-breaks.
/// - Observations, explicit user corrections, and saved self-report answers
///   are separate items with distinct provenance. Generated analysis results
///   and prior inferences are never candidates.
/// - Every included byte is an exact UTF-8 provider-bound byte, counted by
///   `ContextSerializer`; the item, byte, and per-session turn caps of the
///   `BoundedContextBudget` are never exceeded.
/// - Every candidate — observations, corrections, and self-reports alike —
///   is screened against all known private source locators available in the
///   loaded Reflect-owned stores (every stored turn's source path and every
///   event's locator path), so an item quoting another record's imported
///   source path is conservatively omitted entirely and reported. The
///   locators themselves never enter envelopes, provider text, notes, or
///   logs.
/// - Earlier-versus-recent comparison is explicit: a missing earlier side is
///   reported as missing (or not assessable), never as evidence.
public struct ContextRetriever {
    /// A relevant item is truncated only when at least this many bytes of
    /// usable text remain; below this, the item is omitted instead of
    /// including a uselessly small fragment.
    static let minimumTruncationBytes = 64

    private let persistence: PersistenceController
    private let serializer: ContextSerializer

    public init(persistence: PersistenceController, serializer: ContextSerializer = ContextSerializer()) {
        self.persistence = persistence
        self.serializer = serializer
    }

    public func retrieve(_ request: ContextRetrievalRequest, now: Date = Date()) throws -> ContextEnvelope {
        let stores = try loadStores()
        let budget = request.budget
        // Every private source locator known to the loaded stores screens
        // every candidate, not just each record's own locator.
        let knownLocators = Self.knownPrivateLocators(sessions: stores.sessions, events: stores.events)

        // Build and render the full candidate pool once so privacy screening
        // and neighbor windows behave identically for relevant items and
        // window neighbors.
        var pool = candidatePool(sessions: stores.sessions, events: stores.events, reports: stores.reports)
        let correctionsByEvent = Self.correctionsMap(stores.corrections)
        var correctionCandidates: [String: Candidate] = [:]
        for (eventID, correction) in correctionsByEvent {
            var candidate = Self.correctionCandidate(correction)
            candidate.render(against: knownLocators)
            if candidate.excludedReason == nil {
                correctionCandidates[eventID] = candidate
            }
        }
        for index in pool.indices {
            pool[index].render(against: knownLocators)
        }

        // Relevance and scope.
        let terms = request.terms.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        for index in pool.indices {
            pool[index].score = Self.relevanceScore(of: pool[index].item.text, terms: terms)
        }

        var omittedIDs: [String] = []
        var secretOmittedCount = 0
        var locatorOmittedCount = 0
        var unplacedByDateScopeCount = 0

        var relevant: [Candidate] = []
        for var candidate in pool {
            let matchesTerms = terms.isEmpty || candidate.score.distinct > 0
            guard matchesTerms else { continue }
            guard let scope = request.scope else {
                screenPrivacy(&candidate, relevant: &relevant, omittedIDs: &omittedIDs,
                              secretOmittedCount: &secretOmittedCount, locatorOmittedCount: &locatorOmittedCount)
                continue
            }
            if let allowedKinds = scope.sourceKinds, let sourceKind = candidate.item.sourceKind,
               !allowedKinds.contains(sourceKind) {
                continue
            }
            if let allowedIDs = scope.referenceIDs,
               !allowedIDs.contains(candidate.item.sourceRecordID), !allowedIDs.contains(candidate.item.id) {
                continue
            }
            if let interval = scope.dateInterval {
                switch candidate.item.observedAt {
                case .some(let date) where interval.contains(date):
                    break
                case .some:
                    unplacedByDateScopeCount += 1
                    omittedIDs.append(candidate.item.id)
                    continue
                case nil:
                    unplacedByDateScopeCount += 1
                    omittedIDs.append(candidate.item.id)
                    continue
                }
            }
            screenPrivacy(&candidate, relevant: &relevant, omittedIDs: &omittedIDs,
                          secretOmittedCount: &secretOmittedCount, locatorOmittedCount: &locatorOmittedCount)
        }

        guard !relevant.isEmpty else {
            let outcome: ContextOutcomeKind = omittedIDs.isEmpty ? .noRelevantHistory : .relevantHistoryExcluded
            return try envelope(
                request: request,
                now: now,
                budget: budget,
                items: [],
                omittedIDs: omittedIDs,
                truncatedIDs: [],
                includedTurnCount: 0,
                earlierIncludedCount: 0,
                earlierCandidatesExisted: false,
                anyDatedRelevantCandidate: false,
                comparisonRequested: request.requestsEarlierRecentComparison,
                outcome: outcome,
                missingStores: stores.missing,
                includedApproximateTimes: false,
                includedCappedAtImport: false,
                includedMissingSessionIdentity: false,
                secretOmittedCount: secretOmittedCount,
                locatorOmittedCount: locatorOmittedCount,
                unplacedByDateScopeCount: unplacedByDateScopeCount,
                correctionsOmittedCount: 0
            )
        }

        // Earlier-versus-recent classification over the relevant pool.
        let dated = relevant.compactMap { $0.item.observedAt }
        let boundary: Date? = dated.isEmpty ? nil : Self.midpoint(dated.min()!, dated.max()!)
        for index in relevant.indices {
            switch (relevant[index].item.observedAt, boundary) {
            case (.some(let date), .some(let limit)):
                relevant[index].era = date < limit ? .earlier : .recent
            case (.some, nil):
                relevant[index].era = .recent
            case (nil, _):
                relevant[index].era = .undated
            }
        }

        // Deterministic ranked lists.
        let primary: [Candidate]
        let earlierRanked: [Candidate]
        if request.requestsEarlierRecentComparison, dated.isEmpty == false {
            let recent = relevant.filter { $0.era == .recent }.sorted(by: Self.recentComparator)
            let earlier = relevant.filter { $0.era == .earlier }.sorted(by: Self.earlierComparator)
            earlierRanked = earlier
            primary = Self.interleaving(recent: recent, earlier: earlier)
        } else {
            primary = relevant.sorted(by: Self.recentComparator)
            earlierRanked = []
        }

        // Session windows for neighbor expansion.
        let windows = Self.sessionWindows(sessions: stores.sessions, pool: pool)

        // Budget walk with neighbor expansion.
        var includedItems: [ContextItem] = []
        var truncatedIDs: [String] = []
        var includedTurnCount = 0
        var includedBytes = 0
        var perSessionIncluded: [String: Int] = [:]
        var perSessionQueued: [String: Int] = [:]
        var seen = Set(primary.map(\.item.id))
        var queue = primary
        var cursor = 0
        var earlierIncludedCount = 0
        var includedApproximateTimes = false
        var includedCappedAtImport = false
        var includedMissingSessionIdentity = false

        while cursor < queue.count {
            let candidate = queue[cursor]
            cursor += 1

            if includedItems.count >= budget.maxItemCount {
                omittedIDs.append(candidate.item.id)
                continue
            }
            if candidate.item.kind == .observedTurn {
                if includedTurnCount >= budget.maxTurnCount || (perSessionIncluded[candidate.sessionID ?? ""] ?? 0) >= budget.maxTurnCount {
                    omittedIDs.append(candidate.item.id)
                    continue
                }
            }

            var text = candidate.rendered
            var truncated = false
            let fullBytes = text.utf8.count
            let remaining = budget.maxByteCount - includedBytes
            if fullBytes > remaining {
                let marker = ContextSerializer.truncationMarker
                let availableForText = remaining - marker.utf8.count
                if availableForText >= Self.minimumTruncationBytes {
                    text = ContextSerializer.truncatingToUTF8ByteLimit(text, maxBytes: availableForText) + marker
                    truncated = true
                } else {
                    omittedIDs.append(candidate.item.id)
                    continue
                }
            }

            var item = candidate.item
            item.text = text
            item.truncated = truncated
            item.byteCount = text.utf8.count
            includedItems.append(item)
            includedBytes += item.byteCount
            if truncated { truncatedIDs.append(item.id) }
            if candidate.fromEarlierList { earlierIncludedCount += 1 }
            if item.timestampApproximate || item.observedAt == nil { includedApproximateTimes = true }
            if item.retainedTextCappedAtImport { includedCappedAtImport = true }

            if candidate.item.kind == .observedTurn {
                includedTurnCount += 1
            }
            if let sessionID = candidate.sessionID {
                perSessionIncluded[sessionID, default: 0] += 1
                perSessionQueued[sessionID, default: 0] += 1
                includedMissingSessionIdentity = includedMissingSessionIdentity || (windows[sessionID]?.missingSessionIdentity ?? false)
                let slots = budget.maxTurnCount - (perSessionQueued[sessionID] ?? 0)
                if candidate.item.kind == .observedTurn, slots > 0 {
                    let neighbors = windows[sessionID]?.nearestNeighbors(fromSequence: candidate.sequence ?? 0, slots: slots, seen: seen) ?? []
                    for neighbor in neighbors {
                        seen.insert(neighbor.item.id)
                        queue.append(neighbor)
                        perSessionQueued[sessionID, default: 0] += 1
                    }
                }
            }
        }

        // Attach explicit corrections for included observed events; the
        // observed items themselves are never mutated.
        var correctionsOmittedCount = 0
        for included in includedItems where included.kind == .observedEvent {
            guard let candidate = correctionCandidates[included.sourceRecordID] else { continue }
            if includedItems.count >= budget.maxItemCount || includedBytes + candidate.rendered.utf8.count > budget.maxByteCount {
                correctionsOmittedCount += 1
                omittedIDs.append(candidate.item.id)
                continue
            }
            var item = candidate.item
            item.text = candidate.rendered
            item.byteCount = candidate.rendered.utf8.count
            includedItems.append(item)
            includedBytes += item.byteCount
        }

        let outcome: ContextOutcomeKind = includedItems.isEmpty ? .relevantHistoryExcluded : .historyIncluded
        return try envelope(
            request: request,
            now: now,
            budget: budget,
            items: includedItems,
            omittedIDs: omittedIDs,
            truncatedIDs: truncatedIDs,
            includedTurnCount: includedTurnCount,
            earlierIncludedCount: earlierIncludedCount,
            earlierCandidatesExisted: !earlierRanked.isEmpty,
            anyDatedRelevantCandidate: !dated.isEmpty,
            comparisonRequested: request.requestsEarlierRecentComparison,
            outcome: outcome,
            missingStores: stores.missing,
            includedApproximateTimes: includedApproximateTimes,
            includedCappedAtImport: includedCappedAtImport,
            includedMissingSessionIdentity: includedMissingSessionIdentity,
            secretOmittedCount: secretOmittedCount,
            locatorOmittedCount: locatorOmittedCount,
            unplacedByDateScopeCount: unplacedByDateScopeCount,
            correctionsOmittedCount: correctionsOmittedCount
        )
    }

    // MARK: Loaded stores (fail closed)

    private struct LoadedStores {
        let sessions: [WorkSession]
        let events: [EvidenceEvent]
        let corrections: [AttributionCorrection]
        let reports: [DailyReport]
        let missing: [StoreName]
    }

    private func loadStores() throws -> LoadedStores {
        var missing: [StoreName] = []
        var sessions: [WorkSession] = []
        var events: [EvidenceEvent] = []
        var corrections: [AttributionCorrection] = []
        var reports: [DailyReport] = []

        switch persistence.loadSessionsHealth() {
        case .missing: missing.append(.sessions)
        case .loaded(let value): sessions = value
        case .failed(let failure): throw ContextRetrievalFailure.storeDamaged(store: .sessions, message: failure.userMessage)
        }
        switch persistence.loadEventsHealth() {
        case .missing: missing.append(.events)
        case .loaded(let value): events = value
        case .failed(let failure): throw ContextRetrievalFailure.storeDamaged(store: .events, message: failure.userMessage)
        }
        switch persistence.loadCorrectionsHealth() {
        case .missing: missing.append(.corrections)
        case .loaded(let value): corrections = value
        case .failed(let failure): throw ContextRetrievalFailure.storeDamaged(store: .corrections, message: failure.userMessage)
        }
        switch persistence.loadReportsHealth() {
        case .missing: missing.append(.reports)
        case .loaded(let value): reports = value
        case .failed(let failure): throw ContextRetrievalFailure.storeDamaged(store: .reports, message: failure.userMessage)
        }
        return LoadedStores(
            sessions: sessions,
            events: events,
            corrections: corrections,
            reports: reports,
            missing: missing.sorted { $0.rawValue < $1.rawValue }
        )
    }

    // MARK: Candidate pool

    private struct Candidate {
        let item: ContextItem
        let isTurn: Bool
        let sessionID: String?
        let sequence: Int?
        var rendered: String = ""
        var excludedReason: ExclusionReason?
        var era: Era = .undated
        var fromEarlierList = false
        var score: (distinct: Int, occurrences: Int) = (0, 0)

        enum ExclusionReason { case secretShape, privateLocator }
        enum Era { case earlier, recent, undated }

        /// Renders the provider-bound text and screens it against every
        /// known private locator from the loaded stores.
        mutating func render(against privateLocators: [String]) {
            rendered = ContextSerializer().providerText(for: item)
            if ContextSerializer.containsSecretShape(rendered) {
                excludedReason = .secretShape
            } else if ContextSerializer.containsAnyPrivateLocator(rendered, locators: privateLocators) {
                excludedReason = .privateLocator
            }
        }
    }

    /// All private source locators present in the loaded Reflect-owned
    /// stores: every stored turn's source path and every event's locator
    /// path. Deduplicated and sorted for determinism; empty values ignored.
    private static func knownPrivateLocators(sessions: [WorkSession], events: [EvidenceEvent]) -> [String] {
        var locators = Set<String>()
        for session in sessions {
            for turn in session.turns where !turn.sourcePath.isEmpty {
                locators.insert(turn.sourcePath)
            }
        }
        for event in events where !event.evidencePath.isEmpty {
            locators.insert(event.evidencePath)
        }
        return locators.sorted()
    }

    private func candidatePool(
        sessions: [WorkSession],
        events: [EvidenceEvent],
        reports: [DailyReport]
    ) -> [Candidate] {
        var pool: [Candidate] = []
        for session in sessions {
            let turns = session.turns.sorted { $0.sequence < $1.sequence }
            for turn in turns {
                guard let revision = turn.revisions.last else { continue }
                let item = ContextItem(
                    id: turn.id,
                    sourceRecordID: turn.id,
                    kind: .observedTurn,
                    provenance: .observed,
                    role: turn.role,
                    eventKind: nil,
                    observedAttribution: turn.observedAttribution,
                    observedAttributionNote: turn.observedAttributionNote,
                    observedAt: revision.timestamp,
                    timestampApproximate: revision.timestampApproximate,
                    retainedTextCappedAtImport: revision.retainedTextTruncated,
                    sourceKind: session.sourceKind,
                    sessionID: session.id,
                    dayKey: nil,
                    text: revision.retainedText
                )
                pool.append(
                    Candidate(
                        item: item,
                        isTurn: true,
                        sessionID: session.id,
                        sequence: turn.sequence
                    )
                )
            }
        }
        for event in events {
            var content = event.summary
            if !event.detail.isEmpty {
                content += event.summary.isEmpty ? event.detail : "\n" + event.detail
            }
            let item = ContextItem(
                id: event.id,
                sourceRecordID: event.id,
                kind: .observedEvent,
                provenance: .observed,
                role: nil,
                eventKind: event.kind,
                observedAttribution: event.observedAttribution,
                observedAttributionNote: event.observedAttributionNote,
                observedAt: event.timestamp,
                timestampApproximate: event.timestampApproximate,
                retainedTextCappedAtImport: false,
                sourceKind: event.sourceKind,
                sessionID: nil,
                dayKey: nil,
                text: content
            )
            pool.append(
                Candidate(
                    item: item,
                    isTurn: false,
                    sessionID: nil,
                    sequence: nil
                )
            )
        }
        for report in reports.sorted(by: { $0.day < $1.day }) {
            for (answerKey, entry) in report.answers.sorted(by: { $0.key < $1.key }) {
                let item = ContextItem(
                    id: "selfreport|\(report.day)|\(answerKey)",
                    sourceRecordID: report.day,
                    kind: .selfReport,
                    provenance: .selfReport,
                    role: nil,
                    eventKind: nil,
                    observedAttribution: nil,
                    observedAttributionNote: nil,
                    observedAt: entry.updatedAt,
                    timestampApproximate: false,
                    retainedTextCappedAtImport: false,
                    sourceKind: nil,
                    sessionID: nil,
                    dayKey: report.day,
                    text: entry.text
                )
                pool.append(
                    Candidate(
                        item: item,
                        isTurn: false,
                        sessionID: nil,
                        sequence: nil
                    )
                )
            }
        }
        return pool
    }

    private static func correctionCandidate(_ correction: AttributionCorrection) -> Candidate {
        let item = ContextItem(
            id: "correction|\(correction.eventId)",
            sourceRecordID: correction.eventId,
            kind: .userCorrection,
            provenance: .userCorrection,
            role: nil,
            eventKind: nil,
            observedAttribution: nil,
            observedAttributionNote: nil,
            observedAt: correction.updatedAt,
            timestampApproximate: false,
            retainedTextCappedAtImport: false,
            sourceKind: nil,
            sessionID: nil,
            dayKey: nil,
            text: "You corrected the attribution of record \(correction.eventId) to \"\(correction.attribution.label)\". The observed record keeps its original label."
        )
        return Candidate(item: item, isTurn: false, sessionID: nil, sequence: nil)
    }

    private static func correctionsMap(_ corrections: [AttributionCorrection]) -> [String: AttributionCorrection] {
        var map: [String: AttributionCorrection] = [:]
        for correction in corrections {
            guard let existing = map[correction.eventId] else {
                map[correction.eventId] = correction
                continue
            }
            if correction.updatedAt > existing.updatedAt {
                map[correction.eventId] = correction
            }
        }
        return map
    }

    // MARK: Relevance, ordering, windows

    private static func relevanceScore(of text: String, terms: [String]) -> (distinct: Int, occurrences: Int) {
        guard !terms.isEmpty else { return (0, 0) }
        let lowered = text.lowercased()
        var distinct = 0
        var total = 0
        for term in terms {
            var count = 0
            var searchStart = lowered.startIndex
            while let range = lowered.range(of: term, range: searchStart..<lowered.endIndex) {
                count += 1
                searchStart = range.upperBound
            }
            if count > 0 {
                distinct += 1
                total += count
            }
        }
        return (distinct, total)
    }

    private static func recentComparator(_ a: Candidate, _ b: Candidate) -> Bool {
        if a.score.distinct != b.score.distinct { return a.score.distinct > b.score.distinct }
        if a.score.occurrences != b.score.occurrences { return a.score.occurrences > b.score.occurrences }
        switch (a.item.observedAt, b.item.observedAt) {
        case (.some(let ad), .some(let bd)):
            if ad != bd { return ad > bd }
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            break
        }
        return a.item.id < b.item.id
    }

    private static func earlierComparator(_ a: Candidate, _ b: Candidate) -> Bool {
        if a.score.distinct != b.score.distinct { return a.score.distinct > b.score.distinct }
        if a.score.occurrences != b.score.occurrences { return a.score.occurrences > b.score.occurrences }
        switch (a.item.observedAt, b.item.observedAt) {
        case (.some(let ad), .some(let bd)):
            if ad != bd { return ad < bd }
        default:
            break
        }
        return a.item.id < b.item.id
    }

    private static func interleaving(recent: [Candidate], earlier: [Candidate]) -> [Candidate] {
        var queue: [Candidate] = []
        queue.reserveCapacity(recent.count + earlier.count)
        var i = 0
        var j = 0
        while i < recent.count || j < earlier.count {
            if i < recent.count {
                queue.append(recent[i])
                i += 1
            }
            if j < earlier.count {
                var candidate = earlier[j]
                candidate.fromEarlierList = true
                queue.append(candidate)
                j += 1
            }
        }
        return queue
    }

    private struct SessionWindow {
        let missingSessionIdentity: Bool
        let bySequence: [Int: Candidate]
        let maxSequence: Int

        func nearestNeighbors(fromSequence anchor: Int, slots: Int, seen: Set<String>) -> [Candidate] {
            var neighbors: [Candidate] = []
            guard slots > 0 else { return neighbors }
            var distance = 1
            while neighbors.count < slots, distance <= maxSequence + 1 {
                let previous = anchor - distance
                let next = anchor + distance
                var addedAtThisDistance = false
                if previous >= 0, let candidate = bySequence[previous], !seen.contains(candidate.item.id), candidate.excludedReason == nil {
                    neighbors.append(candidate)
                    addedAtThisDistance = true
                }
                if neighbors.count < slots, next <= maxSequence, let candidate = bySequence[next], !seen.contains(candidate.item.id), candidate.excludedReason == nil {
                    neighbors.append(candidate)
                    addedAtThisDistance = true
                }
                if !addedAtThisDistance, previous < 0, next > maxSequence { break }
                distance += 1
            }
            return neighbors
        }
    }

    private static func sessionWindows(sessions: [WorkSession], pool: [Candidate]) -> [String: SessionWindow] {
        let candidatesByTurnID = Dictionary(pool.filter { $0.isTurn }.map { ($0.item.id, $0) }, uniquingKeysWith: { first, _ in first })
        var windows: [String: SessionWindow] = [:]
        for session in sessions {
            let turns = session.turns.sorted { $0.sequence < $1.sequence }
            var bySequence: [Int: Candidate] = [:]
            for turn in turns {
                if let candidate = candidatesByTurnID[turn.id] {
                    bySequence[turn.sequence] = candidate
                }
            }
            windows[session.id] = SessionWindow(
                missingSessionIdentity: session.coverage.missingSessionIdentity,
                bySequence: bySequence,
                maxSequence: turns.map(\.sequence).max() ?? -1
            )
        }
        return windows
    }

    // MARK: Privacy screening

    private func screenPrivacy(
        _ candidate: inout Candidate,
        relevant: inout [Candidate],
        omittedIDs: inout [String],
        secretOmittedCount: inout Int,
        locatorOmittedCount: inout Int
    ) {
        switch candidate.excludedReason {
        case .secretShape:
            secretOmittedCount += 1
            omittedIDs.append(candidate.item.id)
            return
        case .privateLocator:
            locatorOmittedCount += 1
            omittedIDs.append(candidate.item.id)
            return
        case nil:
            relevant.append(candidate)
        }
    }

    // MARK: Envelope assembly

    private static func midpoint(_ a: Date, _ b: Date) -> Date {
        Date(timeIntervalSince1970: a.timeIntervalSince1970 + (b.timeIntervalSince1970 - a.timeIntervalSince1970) / 2)
    }

    private func envelope(
        request: ContextRetrievalRequest,
        now: Date,
        budget: BoundedContextBudget,
        items: [ContextItem],
        omittedIDs: [String],
        truncatedIDs: [String],
        includedTurnCount: Int,
        earlierIncludedCount: Int,
        earlierCandidatesExisted: Bool,
        anyDatedRelevantCandidate: Bool,
        comparisonRequested: Bool,
        outcome: ContextOutcomeKind,
        missingStores: [StoreName],
        includedApproximateTimes: Bool,
        includedCappedAtImport: Bool,
        includedMissingSessionIdentity: Bool,
        secretOmittedCount: Int,
        locatorOmittedCount: Int,
        unplacedByDateScopeCount: Int,
        correctionsOmittedCount: Int
    ) throws -> ContextEnvelope {
        let state: SourceCoverageState = (omittedIDs.isEmpty && truncatedIDs.isEmpty) ? .complete : .partial
        let coverage = try BoundedContextCoverage(
            includedItemCount: items.count,
            omittedItemCount: omittedIDs.count,
            truncatedItemCount: truncatedIDs.count,
            includedByteCount: items.reduce(0) { $0 + $1.byteCount },
            includedTurnCount: includedTurnCount,
            state: state
        )
        let descriptor = try BoundedContextDescriptor(budget: budget, coverage: coverage)

        let earlier: EarlierExamplesCoverage
        if !comparisonRequested {
            earlier = .notRequested
        } else if earlierCandidatesExisted {
            earlier = .included(earlierIncludedCount)
        } else if anyDatedRelevantCandidate {
            earlier = .missing
        } else {
            earlier = .notAssessable
        }

        let datedIncluded = items.compactMap(\.observedAt)
        let dateCoverage = ContextDateCoverage(
            earliest: datedIncluded.min(),
            latest: datedIncluded.max(),
            includesApproximateOrMissingTimes: includedApproximateTimes
        )
        let sourceKinds = Array(Set(items.compactMap(\.sourceKind))).sorted { $0.rawValue < $1.rawValue }

        var notes: [String] = []
        if outcome == .noRelevantHistory {
            notes.append("No relevant stored history matched this request.")
        }
        if outcome == .relevantHistoryExcluded {
            notes.append("Relevant stored records existed, but none could be included; see the coverage omissions and notes.")
        }
        if !missingStores.isEmpty {
            let names = missingStores.map(\.displayName).joined(separator: ", ")
            notes.append("These stores do not exist yet: \(names). Nothing has been stored under them so far.")
        }
        if secretOmittedCount > 0 {
            notes.append("\(secretOmittedCount) relevant item(s) were conservatively excluded because they appeared to contain credentials or secret-shaped content.")
        }
        if locatorOmittedCount > 0 {
            notes.append("\(locatorOmittedCount) relevant item(s) were excluded because they contained private source locations.")
        }
        if unplacedByDateScopeCount > 0 {
            notes.append("\(unplacedByDateScopeCount) relevant record(s) were omitted because their observed time is unknown or outside the requested date range.")
        }
        switch earlier {
        case .missing:
            notes.append("No earlier stored examples were available for comparison; change over time cannot be assessed from this context alone.")
        case .notAssessable:
            notes.append("Relevant records were found, but none carry reliable observed times, so an earlier-versus-recent comparison is not assessable.")
        case .included, .notRequested:
            break
        }
        if includedApproximateTimes {
            notes.append("Some included records have no observed time.")
        }
        if includedCappedAtImport {
            notes.append("Some included records were capped at import; their retained text is incomplete.")
        }
        if includedMissingSessionIdentity {
            notes.append("Some included sessions have no source-provided session identity.")
        }
        if correctionsOmittedCount > 0 {
            notes.append("\(correctionsOmittedCount) correction(s) for included records could not fit within the budget and were omitted.")
        }

        return ContextEnvelope(
            generatedAt: now,
            requestTerms: request.terms,
            comparisonRequested: comparisonRequested,
            items: items,
            omittedItemIDs: omittedIDs,
            truncatedItemIDs: truncatedIDs,
            descriptor: descriptor,
            earlierExamples: earlier,
            outcome: outcome,
            missingStores: missingStores,
            dateCoverage: dateCoverage,
            sourceKinds: sourceKinds,
            uncertaintyNotes: notes
        )
    }
}
