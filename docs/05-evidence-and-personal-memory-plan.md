# Evidence and personal memory implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` for authorized native execution, or `superpowers:subagent-driven-development` when subagent execution is explicitly authorized. Execute task by task using checkbox tracking. Read plan 04; use synthetic fixtures. No commit or real history read without separate authorization.

**Goal:** Give Reflect sufficient private, attributable context to answer growth questions without making the user browse evidence.\
**Architecture:** Normalize approved source records into sessions/turns, derive referenced work episodes, and retrieve bounded context with corrections and coverage. Keep original observations, self-reports, and generated memory separate and versioned.\
**Tech stack:** Swift, Foundation, Codable JSON, SwiftPM; optional system indexing only after measurement.\
**Spec:** [01](01-product-vision-and-requirements.md), sections 4–6 and 9; shared contracts in [04](04-architecture-and-technology-plan.md).

## Global constraints

All spec section 9 constraints apply. Source availability uses metadata only. Import is explicit, read-only, deduplicated, and local. No real source content goes into tests, repository files, screenshots, logs, or public research queries. No hidden AI collection/extraction is authorized.

## Review focus

1. A short preview must not be mistaken for a complete conversation or independent demonstration.
2. Source labels/roles and commit authors must not become claims of human authorship.
3. Growing files, repeated imports, and resumed sessions must preserve stable identities without duplicate turns.
4. Unverified source formats and missing context must yield explicit gaps rather than invented projects or sessions.
5. Retrieval must include corrections and enough neighboring context while honoring consent and input limits.

## 1. Current collection is not yet sufficient

`EvidenceEvent` is a flat record with source, time, kind, summary/detail, source path/line, and observed attribution. It does not establish a rich session/decision/outcome model.

The current Codex adapter caps assistant/user message excerpts at 400 characters, tool output at 200, and stores some tool/reasoning records without substantive detail. The current analysis input further caps previews according to settings, omits the event summary, and does not serialize corrections. This may discard the reasoning context needed to distinguish approval, challenge, verification, or understanding.

Increasing the displayed preview limit cannot reconstruct text already discarded at import. A richer re-import must be explicit; never silently reread originals when the user opens chat.

Current growth counts and timestamps remain useful for coverage. They must not become a proxy for learning, effort, seniority, or market value.

## 2. Source capability matrix

Import support and analysis-agent support are separate capabilities.

| Source | Current boundary from this conversation | Planned progression |
| --- | --- | --- |
| Codex CLI JSONL | Implemented event adapter; richer context is incomplete. | First richer session/turn adapter with synthetic format variants and explicit re-import. |
| Claude Code JSONL | Event adapter exists, synthetic-fixture tested. | Verify normalized turn/session semantics before asserting parity. |
| Copilot CLI JSONL | Event adapter exists with cautious role handling. | Preserve compatibility limits; import support does not authorize CLI analysis. |
| Cursor | Workspace stores detected; format not verified/imported. | Separate opt-in adapter investigation, with synthetic/exported format fixtures and safe read-only access. |
| VS Code Copilot Chat | Detected stores are not proved compatible with Copilot CLI. | Separate format investigation; never reuse the CLI label as compatibility proof. |
| Git | Explicit selected-repository metadata import. | Supplement observed work/outcomes without inferring authorship or skill from commits. |
| Searches/browser work | No implemented browser-history adapter. | First support approved exports or permitted search records already present in imported sessions; broader collection needs a separate reviewed adapter. |
| ActivityWatch | Not integrated; not a required runtime dependency. | Optional future local connector only if its signals improve a defined question. No installation or monitoring by default. |
| User reflection/manual explanation | Existing daily answers, plus proposed chat content. | Store as explicit user content with dates and revisions, separate from observed execution. |

The user's references to WhatsApp, Cursor, and Dia concern experience; they are not automatic consent to inspect those applications' data.

## 3. Local information layers

### Observations

Preserve source-established session IDs, ordering, timestamps, roles, tool actions, and outcome text only when the format supports them. Unknown or approximate fields remain labeled. Keep private source location bookkeeping local.

### Corrections and self-reports

Store attribution corrections independently, as the current model does. Also support conversational corrections to profile or interpretation, explicit aspirations, and explanations of decisions. A user's statement is authoritative about their intention, but a claimed completed action should remain self-reported unless separately observed.

### Derived work episodes

Group a bounded set of turns around a task or decision. Record a concise summary, relevant observations, candidate reasoning, outcome, unresolved questions, and supporting references. Derived episodes are interpretations; extraction versions and coverage travel with them.

Do not invent task/project names from a file path or timestamp alone. Source-provided names can be retained; inferred descriptive titles must be labeled as inferred.

### Long-term memory

Store dated profile and assessment snapshots, important user corrections/aspirations, daily reflections, and next steps. Preserve the history of changes instead of overwriting the past with the latest flattering description.

A previous AI assessment does not constitute new evidence that the user has a skill. Retrieval may use it for continuity, but any renewed claim must still link to observations or explicitly labeled self-report.

## 4. Retention, privacy, and permission

Offer understandable local retention choices when introducing richer import. Retain enough approved conversation context to support useful interpretation; avoid blanket copying of every machine history. Separate local display previews from retained context so a compact UI does not require destroying useful private context.

Store richer retained content only in Reflect's Application Support directory. Do not promise encryption at rest unless it is actually implemented and verified. The present local JSON model is not automatically an encrypted vault.

Exclusions apply before reading. Remove credentials/private keys from provider-bound context; do not send source paths or raw unrelated tool output by default. Sensitive-content handling must be tested with synthetic secret-shaped strings rather than real secrets.

Disabling a source blocks future reads but does not silently delete prior imported data. Define imported-data removal separately and update dependent indexes, profile references, and coverage. Deleting a local import must never delete the original history.

No retrieval call may reach outside Reflect's owned store. Broader agent file tools are not a substitute for approved import.

## 5. Deduplication and identity

Prefer source-provided session/turn identifiers. Otherwise derive stable identities from source identity, record coordinates, and canonical record content using system facilities. An amended record gets a new import revision; do not duplicate the entire session on every import.

Record source file progress and schema/parser version in manifests. Handle partial lines, malformed lines, appended files, resumed sessions, approximate dates, timezone changes, and duplicated exported files. Stable identity tests must precede performance claims.

Observed records and explicit corrections remain distinct. If a source amendment invalidates a derived episode, mark the episode/snapshot stale or superseded rather than silently rewriting its historical basis.

## 6. Retrieval policy

Start with transparent local selection using dates, source/session linkage, terms, relevant dimensions, and user corrections. Embeddings or a vector database are not required for the first useful release. Any later embedding provider requires explicit transmission consent and a measurable retrieval benefit.

Proposed initial limits, subject to validation at milestone M1:

- `ContextBudget.maxUTF8Bytes = 32_768`.
- `maxEvidenceItems = 24` referenced items/windows.
- `maxTurnsPerSession = 12` neighboring turns in an included window.

These are engineering test values, not user-approved final product constants or exact token/cost estimates. If trimming is needed, preserve correction/attribution/coverage labels and complete selected statements where possible. Mark every truncated or omitted region.

For a progress comparison, retrieve both relevant earlier and recent examples. Recent-only context cannot establish improvement. For a daily question, prioritize the day's important uncertainty rather than the largest transcript.

The `ContextEnvelope` reports included references, omissions, date/source coverage, and the difference between observations, self-reports, and prior interpretations. User-facing scope remains concise; detailed context inspection is optional.

## 7. Files and interfaces

Modify `Models/EvidenceEvent.swift` only through backward-compatible schema evolution. Extend `Services/Importers/CodexImporter.swift`, `JSONLImportEngine.swift`, and `ImportOrchestrator.swift` for richer explicit import. Review `EvidenceIdentity`, `EventDeduplicator`, `SourceManifest`, `SourceScanner`, and `ExclusionPolicy` before changing identity or availability behavior.

Create the session/turn/episode/reference/coverage models from plan 04, `Services/Context/ContextRetriever.swift`, `ContextBuilder.swift`, and `ContextSerializer.swift`. Add versioned private stores in `IntelligencePersistenceController.swift` and focused tests:

- `SessionImportTests.swift`.
- `ContextRetrievalTests.swift`.
- `ContextPrivacyTests.swift`.
- `MemoryProvenanceTests.swift`.

**Interfaces:** `ContextProviding.build(for:budget:)` consumes only owned-store records and produces a `ContextEnvelope`. A richer importer returns normalized session/turn data plus coverage; the orchestrator owns deduplication/persistence and explicit consent. It must not call an AI service while importing.

## 8. Tasks

### Task E1: Richer Codex context without changing read permissions

- [ ] Write synthetic fixtures for long messages, injected user-role context, resumed sessions, absent IDs/times, appended files, and malformed/unknown records.
- [ ] Assert meaningful session ordering and complete retained selected messages; assert display previews can remain short and truncation is labeled.
- [ ] Implement normalization and explicit re-import; preserve old event-only data as limited coverage.
- [ ] Verify repeated import adds no duplicate turns and an amended turn records a revision.
- [ ] Run `swift run reflect-test-runner`; verify source fixture bytes are unchanged.

### Task E2: Versioned private memory stores

- [ ] Add round-trip, malformed-store, failed-write, migration, and interrupted-write tests for sessions, episodes, and snapshots.
- [ ] Implement persisted records with schema versions and private content references.
- [ ] Verify corrections and AI interpretations cannot overwrite original observations.
- [ ] Verify data removal invalidates dependent references and rebuildable indexes without touching sources.
- [ ] Inspect repository fixtures/log output for synthetic data only.

### Task E3: Bounded context with corrections and coverage

- [ ] Test `retrievalIncludesCorrection`, `comparisonRetrievesEarlierAndRecent`, `missingEarlierContextIsUnknown`, `trimmingMarksOmissions`, and `untrustedTextDoesNotChangeScope`.
- [ ] Implement the initial retrieval policy and serializer with the proposed limits.
- [ ] Verify no original history is read when querying or opening a conversation.
- [ ] Confirm secret-shaped strings/source paths are not sent by default and excluded records never enter the envelope.
- [ ] Use deterministic synthetic scenarios to inspect context quality, not just serialized byte count.

### Task E4: Additional source readiness

- [ ] Expand Claude/Copilot only after parser fixtures establish the expected richer format.
- [ ] Create separate Cursor/VS Code/exported-search compatibility tasks with clear supported versions and failure behavior.
- [ ] Keep unverified sources visibly unavailable; never imply collection of searches/work that the app cannot currently observe.
- [ ] Document coverage limitations in the interface and update `INTEGRATIONS.md` before release.

## 9. Completion gate

At least one approved source must provide enough contextual continuity for the synthetic conversation/reflection journey. Every assessment input includes corrections and coverage, repeat imports are stable, histories remain unread during retrieval, and generated memory cannot promote itself into factual evidence.

## 10. Research references

[Anthropic Contextual Retrieval](https://www.anthropic.com/engineering/contextual-retrieval) explains why isolated chunks can lose relevant meaning. [Effective context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) discusses selective context and durable notes rather than loading all history into each request. These inform the design; they do not require adopting Anthropic as Reflect's provider.
