import Foundation

/// Idempotent merge of a normalized session into the persisted sessions
/// store, per the M2 identity rules:
///
/// - Identical re-imports change nothing and add no turns.
/// - An amended source record becomes a retained new revision linked to the
///   unchanged stable turn identity; earlier revisions are never erased.
/// - Appended or resumed files extend the same session without duplicating
///   turns. Deduplication follows source identity first: stable turn IDs
///   already encode the source-provided record ID or the record's own file
///   coordinates, so a re-scanned record always matches its earlier turn.
///   Only across different files of the same session, one further narrow
///   rule applies: an identical canonical record at the identical line is
///   treated as the same replayed record (an exact copy or replayed history
///   prefix). Content alone never merges records — distinct records,
///   including same-content turns at different lines of one file, are
///   always preserved.
/// - Turn order is stable: existing turns keep their positions, new turns
///   append at the end, and sequences are renumbered over the ordered list.
enum SessionMerger {
    struct Delta: Equatable {
        let addedSessions: Int
        let addedTurns: Int
        let revisedTurns: Int

        var changed: Bool { addedSessions > 0 || addedTurns > 0 || revisedTurns > 0 }
    }

    static func merge(
        existing: [WorkSession],
        incoming: WorkSession,
        importedAt: Date
    ) -> (sessions: [WorkSession], delta: Delta) {
        var result = existing

        guard let index = result.firstIndex(where: { $0.id == incoming.id }) else {
            result.append(incoming)
            return (result, Delta(addedSessions: 1, addedTurns: incoming.turns.count, revisedTurns: 0))
        }

        var session = result[index]
        var addedTurns = 0
        var revisedTurns = 0

        for turn in incoming.turns {
            guard let incomingRevision = turn.revisions.last else { continue }
            if let turnIndex = session.turns.firstIndex(where: { $0.id == turn.id }) {
                guard session.turns[turnIndex].revisions.last?.revisionID != incomingRevision.revisionID else {
                    continue
                }
                session.turns[turnIndex].revisions.append(incomingRevision)
                revisedTurns += 1
            } else if let incomingLine = turn.sourceLine,
                      session.turns.contains(where: { existing in
                          existing.sourcePath != turn.sourcePath
                              && existing.sourceLine == incomingLine
                              && existing.revisions.last?.revisionID == incomingRevision.revisionID
                      }) {
                // The same source record replayed in another file of this
                // session (an exact copy or a replayed history prefix):
                // identical canonical content at the identical record
                // coordinate, so it is not a distinct turn. Same-content
                // records at different lines — in any file — never reach
                // this branch and are always preserved as distinct turns.
                continue
            } else {
                var appended = turn
                appended.sequence = session.turns.count
                session.turns.append(appended)
                addedTurns += 1
            }
        }

        if addedTurns > 0 || revisedTurns > 0 {
            session.importRevision += 1
            session.lastImportedAt = importedAt

            session.coverage = CoverageSummary.derived(
                from: session.turns,
                missingSessionIdentity: session.coverage.missingSessionIdentity,
                parserVersion: incoming.coverage.parserVersion,
                parserUncertaintyNotes: session.coverage.unioningUncertaintyNotes(incoming.coverage).parserUncertaintyNotes
            )

            if let incomingStart = incoming.startedAt {
                if let currentStart = session.startedAt {
                    if incomingStart < currentStart {
                        session.startedAt = incomingStart
                        session.startedAtApproximate = incoming.startedAtApproximate
                    }
                } else {
                    session.startedAt = incomingStart
                    session.startedAtApproximate = incoming.startedAtApproximate
                }
            }
            let activityTimes = session.turns.compactMap { $0.revisions.last?.timestamp }
            session.lastActivityAt = activityTimes.max()
        }

        result[index] = session
        return (result, Delta(addedSessions: 0, addedTurns: addedTurns, revisedTurns: revisedTurns))
    }
}
