# 11 — Shared contracts and persistence

Status: M1 shared contracts and versioned persistence were accepted at synthetic source/test/build gates. M2 adds normalized Codex session/turn records in a separate version-1 `sessions.json` store; the five M1 stores, schemas, payloads, IDs, and deduplication behavior remain unchanged. The additive store uses the accepted envelope, failure, recovery, and migration contracts below. M2 proof is synthetic temporary-fixture source/test/build evidence only; no owner's store or source history was opened during M2.

## Claim provenance

`ClaimProvenance` has exactly four meanings, and they stay distinct:

| Case | Raw value | Meaning |
| --- | --- | --- |
| `observed` | `observed` | Structural fact recorded at import time. Never asserts human authorship. |
| `inferred` | `inferred` | The app's own conclusion from observations. Separable from what was observed; may be wrong. |
| `selfReport` | `self_report` | A statement the user made about themselves, taken as a report, not as verified fact. |
| `userCorrection` | `user_correction` | The user's explicit override of a previously recorded value. |

Decisions:

- A correction is its own provenance and its own record. It never mutates the observation it corrects. `AttributionCorrection` is persisted in the separate `corrections.json` store, and `EvidenceEvent.observedAttribution` stays exactly as imported, so corrections survive re-imports and deletions and can themselves be revised.
- Inference is always labeled as app-generated; observations and inferences are never merged into one value at rest.

## Qualitative confidence

`ClaimConfidence` is a small ordered vocabulary with no numeric scores:

`insufficient_evidence` < `low` < `moderate` < `high`

Decisions:

- `insufficientEvidence` is a first-class outcome meaning "not assessable from the evidence so far" — Reflect shows that state rather than fabricating a competence assessment.
- Ordering is by assessment strength only; no percent scores, grades, or numeric scales exist anywhere in the contract.

## Capability availability

`CapabilityAvailability` has exactly four states: `available`, `unavailable`, `unverified`, `disabled`.

Decisions:

- Detected does not imply verified. A capability that is present but not yet verified must be reported as `unverified`, never as `available`.
- `disabled` is reserved for user-explicit opt-out and is distinct from `unavailable` (not usable on this machine).

## Bounded-context metadata

`Sources/ReflectLib/Models/BoundedContext.swift` adds metadata-only types that describe the size contract of a bounded context and the coverage it actually achieved. They record no context content, no retrieval algorithm, no source reading, and no AI invocation.

`BoundedContextBudget` — the explicit positive budget:

| Field | Meaning |
| --- | --- |
| `maxItemCount` | Maximum number of items the context may include. |
| `maxByteCount` | Maximum size of included content in UTF-8 encoded bytes. |
| `maxTurnCount` | Maximum number of conversation turns the context may include. |

`BoundedContextCoverage` — what the context actually included:

| Field | Meaning |
| --- | --- |
| `includedItemCount` | Items made part of the context. |
| `omittedItemCount` | Relevant items left out entirely. |
| `truncatedItemCount` | Items only partially included. |
| `includedByteCount` | Size of the included content in UTF-8 encoded bytes. |
| `includedTurnCount` | Conversation turns included. |
| `state` | One of the source coverage states below. |

`SourceCoverageState` has exactly four states: `complete`, `partial`, `unavailable`, `unknown`.

- `complete`: every relevant source item was included; nothing was omitted or truncated. Requires `omittedItemCount == 0` and `truncatedItemCount == 0`.
- `partial`: some relevant items were omitted or truncated. Requires at least one of `omittedItemCount` or `truncatedItemCount` to be positive.
- `unavailable`: the underlying source could not be read at all, so nothing could be included. Requires every count to be zero: no source content was read and the exact coverage counts are unknown.
- `unknown`: coverage was not assessed (or not yet assessed). A real outcome, never an error or an empty value. No count relation is enforced.

`BoundedContextDescriptor` pairs one budget with the coverage achieved under it.

Decisions:

- Byte counts always mean UTF-8 encoded bytes, both for budget maxima and coverage totals.
- A budget is explicitly positive: every maximum must be at least 1. A zero or negative budget is not a valid state.
- Coverage counts are nonnegative. There is no negative or "unset" count sentinel; an unassessed coverage is expressed by `state: .unknown`, never by magic numbers.
- Included item, byte, and turn totals may never exceed the paired budget's maxima.
- The coverage `state` must agree with its counts; violations are a distinct validation error (`stateInconsistentWithCounts`), enforced at construction and inherited by the descriptor and by every decoding path.
- Validation runs at direct initialization and again at every decoding. Decoding throws (`DecodingError`) on out-of-range persisted values or state/count contradictions, so a corrupt persisted descriptor can never bypass the invariants.

## Store identity and schema version

Reflect's M1 persistence contained five JSON stores. M2 adds a sixth, `sessions.json`, under the same private Application Support folder. Store identity is `StoreName`; it is stable, and each store keeps its file name:

| Store | File | Current schema version |
| --- | --- | --- |
| `events` | `events.json` | 1 |
| `corrections` | `corrections.json` | 1 |
| `reports` | `reports.json` | 1 |
| `settings` | `settings.json` | 1 |
| `manifests` | `manifests.json` | 1 |
| `sessions` | `sessions.json` | 1 |

Decisions:

- `StoreName.schemaVersion` records the on-disk JSON shape version; all six stores currently sit at version 1. The five M1 stores keep their original file names, schema versions, and payload shapes. Future shape changes bump the version per store without renaming files, so readers can branch without breaking store identity.
- Since M1, current store files are version-1 envelopes (`store`, `schemaVersion`, `payload`) written by `StoreFileWriter`; the payload Codable shapes inside the envelope are unchanged. Legacy bare payloads written before envelopes existed read as schema version 0.

## Versioned persistence and migration

Implemented in `Sources/ReflectLib/Services/Persistence/` (`StoreEnvelope.swift`, `PersistenceController.swift`, `StoreMigration.swift`, `StoreMigrationManifest.swift`):

- Two readable generations: `StoreFileReader` accepts a current version-1 envelope or a legacy bare payload (treated as schema version 0, read exactly without changing bytes). Everything else — malformed payloads or envelopes, wrong-store envelopes, invalid versions, and newer unsupported schemas — is a typed `StoreFileRejection`, never silently defaulted.
- Legacy reads are read-only: an ordinary save refuses to replace a legacy bare file (`legacyNeedsMigration`) so the original survives until the explicit migration path can preserve it with a protected backup. Ordinary saves fail closed on corrupt, wrong-store, invalid-version, unsupported-newer, and legacy bytes; existing files stay byte-for-byte untouched.
- Explicit recovery: `PersistenceController.recoverStore(_:)` backs up a damaged store's original bytes under `Damaged Backups/` inside the private store directory and verifies them byte-for-byte before installing a fresh version-1 envelope; any failure leaves the original recoverable.
- Migration is explicit and local: `PersistenceController.migrateLegacyStores()` is the only way migration starts — nothing runs at startup — and it operates only on its configured directory. Missing and already-current stores are no-ops; it returns `.alreadyCurrent` when there is nothing to migrate.
- Preflight before mutation: every present store is classified before any byte changes. Corrupt, wrong-store, malformed, and newer files abort the migration untouched; errors are never treated as empty stores.
- Verified retained originals: each legacy store's exact bytes are copied to `Migration Backups/<migration UUID>/<store>.json` and verified against a recorded SHA-256 hash before any replacement; backups are kept indefinitely.
- Private structural manifest: `manifest.json` journals each phase (`backingUp`, `applying`, `complete`, `rollingBack`, `rolledBack`) and per-store flags before the matching mutation. It records only relative backup names, hashes, and progress — never payload content, transcript strings, or absolute paths. An unreadable manifest fails closed: the directory counts as migration-locked.
- Staged, journaled replacements: version-1 target envelopes are staged, hash-verified on disk, and decode round-trip validated (payload equality is checked, never assumed) before any original is replaced; each atomic replacement is journaled before it happens.
- Retry safety: a retry re-derives each participant's byte state from disk. A store file must hash to exactly the recorded original bytes or the pinned target bytes, or the migration stops (`externalByteChange`) without overwriting; repeating a completed migration is an idempotent no-op that creates no new backups.
- In-progress lock: while a migration or rollback is in progress, ordinary reads fail typed and ordinary saves are refused (`migrationInProgress`), so no mixed on-disk generation is ever consumed or written.
- Explicit rollback: `PersistenceController.rollbackLegacyStoreMigration()` restores every participant to its exact legacy original bytes from the verified backups, is itself resumable from the journal, and keeps the manifest and backups with a `rolled-back` status. Nothing ever rolls back or cleans up automatically.

Proof limits: all versioning, write-block, recovery, migration, interruption/retry, rollback, and lock behavior is proven by synthetic tests against temporary fixtures (`PersistenceMigrationTests`, `StoreVersioningTests`, `StoreFailureTests`). No runtime migration occurred and no real user store was opened or migrated.

## Record identity

Existing record identifiers are unchanged and source-compatible; no ID wrapper types are introduced:

- `EvidenceEvent.id` is a `String` holding an opaque stable digest identity. `EvidenceIdentity.stableID` (`Sources/ReflectLib/Support/EvidenceIdentity.swift`) builds the stable key as `source raw value | path | line (or "-" when absent) | record type`, hashes it with SHA-256, and stores the first 16 digest bytes as 32 lowercase hex characters. The same source record always produces the same ID, which is what makes repeated imports idempotent; the readable source/path/locator parts stay in the key and never appear in the persisted ID itself.
- `DailyReport.id` stays the day key: report identity is the civil day it reflects.
- `AttributionCorrection` is keyed by the event it corrects (`id` equals `eventId`).
- App-owned new records (records Reflect itself creates, with no external source locator) may use `UUID` strings; they share the same plain `String` ID type.

## M2 normalized session and turn records

`WorkSession`, `ConversationTurn`, `TurnRevision`, and `CoverageSummary` live in `Sources/ReflectLib/Models/Intelligence/`. They are separate records in `sessions.json`; they do not alter or replace `EvidenceEvent` observations. The explicit `SessionImportService` is the only current path that reads a selected Codex source file or loads/saves normalized sessions. App startup and retrieval do not read source histories.

- Session and turn identities use a separate SHA-256 ID space from `EvidenceEvent.id`. Valid source session/turn IDs are retained in their explicit source-ID fields and scoped to the source. Missing turn IDs use source file/line coordinates; missing session IDs use a file-scoped identity and set `missingSessionIdentity` in coverage.
- A changed record at the same stable turn identity appends a `TurnRevision`; prior revisions remain stored. Reimporting the current identical record does not rewrite the sessions store. Duplicate-file replay is deduplicated only when it matches a different file at the same source line and with identical canonical content; content alone never collapses distinct same-file turns.
- Full selected text is retained separately from the shorter `localPreview`. Retention and preview caps are labeled independently. User-role records remain attribution-unclear because that role may contain injected context. Paths remain local bookkeeping and are not task/project labels.
- Coverage records retained turns, approximate/missing times, truncation, missing source session identity, parser version, and parser uncertainty notes for malformed or skipped records. Codex parsing has synthetic-format coverage only; no compatibility claim is made for unverified rollout variants.

### Additive sessions-store migration

The `.sessions` store is absent from older installations. Explicit migration leaves it absent when it is missing. If a legacy bare `sessions.json` is present, it participates in the same all-present-store preflight, verified backup, version-1 envelope staging, journal, retry, rollback, and migration lock as the other stores. Corrupt, wrong-store, and unsupported versions fail closed without changing bytes. Synthetic tests cover absent/present cases, retained original bytes, retry, rollback, recovery, and lock behavior. No real migration was run.

## LocalDay identity

`LocalDay` identifies a civil day by calendar identifier, time zone identifier, and year/month/day together. Identity and equality include every field: the same instant can belong to different civil days under different time zones, and a persisted day's identity never silently moves when the machine's time zone changes. Construction from an instant always takes the `Calendar` and `TimeZone` explicitly; the machine's current time zone is never used for persisted identity.

## M2 local context retrieval

`ContextRetriever` loads only Reflect-owned versioned stores through `PersistenceController`; it receives no source URL and cannot scan or reopen imported histories. Selection is deterministic and term/recency based. When comparison is requested, relevant recent and earlier examples are interleaved when available; missing or unassessable earlier coverage stays explicit. Neighboring turns are bounded per selected session. Observed turns/events, user corrections, and saved self-report answers remain separate typed items; generated analysis and prior inferences are not promoted into observations.

`ContextSerializer` renders role/provenance labels without source paths or line locators, screens secret-shaped text and known private locators, and labels UTF-8-safe truncation. Retrieval coverage counts the exact UTF-8 bytes of included provider-bound items, including each item's label and text, under the M1 `BoundedContextBudget`; item and turn maxima are also enforced. The serialized document's structural coverage/budget/date/source headers are framing metadata and are not included in `includedByteCount`. Thus the cap describes included context items, not total document framing overhead. Every candidate is screened against all source locators present in the loaded session/event stores, including self-reports and corrections that quote another record's path. A path absent from those stores cannot be detected by this exact-locator screen. No provider call or consumer UI is part of this slice.

Synthetic tests cover earlier/recent and missing comparison coverage, neighbor and item/byte/turn limits, truncation/omissions, corrections/self-reports, user-role ambiguity, missing metadata, damaged stores, secret/path exclusion, preview separation, and retrieval stability after a synthetic source file is changed or deleted. These are source/test/build results only; they do not establish live source compatibility, provider behavior, or runtime UI behavior.

## M1 scope

M1 added the vocabulary (including the bounded-context metadata above) with its exact Codable behavior, the persistence identity rules, and the versioned store format with fail-closed ordinary writes, explicit recovery, and explicit migration/rollback. M2 adds the separate normalized session/turn store, explicit Codex import service, and local bounded retrieval described above. Existing M1 payload shapes and event identities remain source-compatible. No consumer UI or provider invocation is included in this M2 slice.
