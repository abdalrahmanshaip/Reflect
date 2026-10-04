# Current-state audit and repair implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` for authorized native execution, or `superpowers:subagent-driven-development` when subagent execution is explicitly authorized. Execute task by task using checkbox tracking. These are planned behaviors, not completed fixes. Do not commit automatically.

**Goal:** Make Reflect's storage, Settings access, and feedback trustworthy before extending its intelligence.\
**Architecture:** Preserve the existing library/app separation and repair store/persistence boundaries before restructuring UI. Move agent discovery off the UI actor, make operation states explicit, and test adverse conditions with injected services.\
**Tech stack:** Swift, SwiftUI, Foundation, AppKit where needed, SwiftPM, the existing synthetic test runner.\
**Spec:** [01 — Product vision and requirements](01-product-vision-and-requirements.md).

## Global constraints

All constraints in spec section 9 apply, including macOS 13, English, system frameworks only, explicit imports/AI invocation, synthetic fixtures, preservation of dirty work, and no commit. Tests must never use the owner's actual Application Support store.

## Review focus

1. A corrupt or unreadable store must not become an apparently new empty account and be overwritten.
2. A failed write must not publish saved/reflected state or silently lose the current draft.
3. Slow or hung CLI discovery must not prevent Settings from appearing and accepting input.
4. An attribution correction shown to the user must reach analysis as a separate correction.
5. Navigation/import completion during editing must not erase drafts or quietly change a question's basis.

## 1. Audit evidence and limits

The 1 October audit in this conversation included source review, three research agents, 122 passing tests, a successful UI fixture build, and runtime inspection of Today, This Week, Patterns, and Settings using 2,000 synthetic records. These are historical results, not checks rerun for this documentation task or guarantees for later code.

The Mac locked before remaining desktop checks. All Records, Sources, record detail, narrow/Dark layouts, complete keyboard traversal, and VoiceOver tasks were not fully proved in that pass. No real histories, credentials, imports, or analysis requests were inspected or run.

The sidebar Settings button opened Settings in the synthetic app. The user's actual failure was not reproduced. Installed and release executables shared a Mach-O UUID; differing hashes did not establish a stale build. A stale-binary explanation therefore remains unproven.

## 2. Why the application feels unfinished

| Area | Existing behavior | Implication for the redesign |
| --- | --- | --- |
| Product outcome | Counts, source names, timestamps, generic questions, and reports dominate. | The primary flow must answer growth questions and follow up on decisions. |
| Desktop integration | Split view exists, but application commands and Settings scene are thin/missing. | Familiar Mac behavior needs deliberate scene/menu/focus work. |
| Composition | Narrow journal-like reading column, serif report/question/editor text, repeated explanatory labels. | Rebalance around a capable conversation and clear actions; typography alone will not fix usefulness. |
| Continuity | Root detail uses route-based identity; much state lives inside disposable views. | Keep conversation, drafts, filters, and positions in durable route/store state. |
| Intelligence | Current growth summary counts activity; daily questions are deterministic templates. | Counts describe coverage, not demonstrated improvement. Build richer context and interpretation. |
| Trust | Save/load and analysis feedback can contradict actual persistence or transmission. | Repair these before asking the user to trust assessments. |

## 3. Findings register

Source line numbers can move; the files and symbols below are the stable lookup points.

| ID | Priority | Finding | Proof status | Relevant files/symbols |
| --- | --- | --- | --- | --- |
| A01 | High | `loadAll` suppresses decoding/read errors and substitutes empty/default values. A subsequent save can replace malformed stored reports. | Fixed; synthetic recovery and failed-store preservation independently verified. | `Stores/AppStore.swift`, `Services/Persistence/PersistenceController.swift`. |
| A02 | High | `saveReport` mutates published reports before persistence; failed save can still mark the day reflected. | Fixed; synthetic obstructed-store scenario independently proved failed drafts do not publish and durable state remains. | `AppStore.saveReport`, `Views/ReflectionComposerView.swift`. |
| A03 | High | Analysis input omits explicit attribution corrections shown in selected rows. | Fixed; selected corrections serialize separately from observed attribution in fake-runner tests. | `Services/Provider/AnalysisService.swift`, `Models/AttributionCorrection.swift`. |
| A04 | Medium | Settings entry performs synchronous sequential CLI status checks on the main-actor path, with an eight-second timeout per agent. | Fixed; delayed synthetic discovery remains responsive and cancellable. The reported symptom itself was not reproduced, so its cause remains unknown. | `Views/SettingsView.swift`, `AnalysisAgentDiscovery.swift`, `AnalysisProcessRunner.swift`. |
| A05 | Medium | No dedicated Settings scene or supported Command-comma wiring. | Fixed; sidebar and Command-comma opened the native scene in the synthetic fixture. macOS 13 fallback has source/build proof only. | `Sources/ReflectAppMain/AppMain.swift`, `ContentView.swift`, `ReflectSidebarView.swift`. |
| A06 | Medium | Ready analysis copy says nothing was sent even after completion/restoration; outer privacy status may not observe reference-model changes. | Fixed in source and model/state tests; synthetic screenshot verifies idle parent-line rendering. Non-idle status transitions were not visually exercised. | `OptionalAnalysisView.swift`, `TodayView.swift`, analysis view model. |
| A07 | Medium | Questions can remain stale when an import completes while Today remains visible. | Fixed in source and synthetic state tests: a day-evidence identity change is shown while the active question and draft remain unchanged. The notice was not visually exercised in a live fixture. | `TodayView.swift`, `ReflectionDraftModel.swift`, `ReportGenerator.swift`. |
| A08 | Medium | Bulk import tries sources broadly and lets individual summaries overwrite the aggregate result. | Fixed at the scheduling boundary with keyed per-source results; synthetic executor and persistence tests pass. Sources card rendering has build proof only, not live UI proof. | `AppStore.importAllAvailable`, `ImportRules.swift`, `ImportSourceResult.swift`, `SourcesView.swift`. |
| A09 | Medium | Filtered empty results say no events exist rather than no matches. | Fixed in source and synthetic state tests: an empty store keeps import guidance; a filter miss has distinct copy and a clear-filter action. Live clear-filter activation remains unverified because the Mac was locked; carry this interaction check forward. | `TimelineView.swift`, `TimelineEmptyState.swift`, `TimelineEmptyStateTests.swift`. |
| A10 | Medium | Navigation/hover/accessibility tests prove helpers, not full Settings, pointer, keyboard, or VoiceOver behavior. | Source and helper tests verified; broader rendered pointer, keyboard, and VoiceOver checks remain open for native validation. | `NavigationTests`, `HoverAffordanceTests`, `RowAccessibilityTests`. |
| A11 | Medium | Performance fixture uses repeated literal index text for IDs/paths. | Fixed in source and synthetic tests: stable record IDs and unique source/path/line locators are checked at 2,000 records, and every benchmark scale is validated before timing. | `SyntheticPerformanceTests.swift`. |
| A12 | Validate | Future-day navigation, session Show all opening day-wide results, non-scrolling record detail, About dismissal, and locale-dependent dates need checks. | Validated individually in source, a focused synthetic test, and debug builds. Next-week navigation is disabled at the current week; upcoming weekdays inside the current week remain selectable because no product rule prohibits them. Show all opens all record types and sources for its selected day. Record detail scrolls independently with its title and Done action fixed. About has a Done/cancel action. Date labels use English formatters and the new test covers weekday, full date, date/time, sidebar, and week-range labels. Native click-through and a non-English-locale runtime demonstration remain unverified because the Mac is locked. | `WeeklyView`, `TodayEvidenceInspector`, `ContentView`, `TimelineView`, `EvidenceSheet`, `AboutView`, `Fmt`, `WeekCalendar`, `NavigationTests`. |

The existing record screen has no full text search, and Patterns bars do not lead to relevant context. These are capability gaps, not reasons to make evidence browsing the new primary flow.

## 4. File responsibilities

Modify `PersistenceController.swift` for typed load/write results and safe first-write/replacement behavior. Modify `AppStore.swift` for persist-before-publish semantics and aggregate import outcomes. Keep unsaved text in `ReflectionDraftModel.swift` rather than treating it as persisted report content.

Create `Models/StoreHealth.swift` for per-store health (`missing`, `loaded`, `failed`) and `Support/OperationState.swift` for explicit operation status. Add focused failure tests to `PersistenceTests.swift` or new `StoreFailureTests.swift`, `SettingsDiscoveryTests.swift`, and `ImportBatchTests.swift`; register them in `RunnerMain.swift` using the existing harness.

New file names are proposed interfaces, not claims that these files exist today.

## 5. Tasks

### Task A: Distinguish absent storage from unreadable storage

**Interfaces:** Introduce `StoreLoad<Value>` with `missing`, `loaded(Value)`, and `failed(StoreFailure)` outcomes. `StoreFailure` contains store identifier and a safe user message, never file contents. Keep `PersistenceController` throwing methods usable during migration; `AppStore` records health explicitly.

- [x] Add synthetic tests `missingStoreAllowsFirstSave`, `malformedStoreIsNotEmptySuccess`, and `unreadableStoreBlocksReplacement`. Assert malformed bytes remain unchanged after a rejected ordinary save.
- [x] Run `swift run reflect-test-runner`; verify each new test fails for the intended existing defect.
- [x] Implement typed health handling. Ordinary editing may continue as an unsaved draft, but affected-store writes are blocked until a deliberate recovery action resolves the failure.
- [x] Test first creation, atomic replacement, backup failure, and failed recovery separately. Recovery must preserve original bytes in private Application Support storage; it must not reset silently.
- [x] Run the runner and inspect the recovery screen with a synthetic damaged store. Verify no raw payload appears in logs.

### Task B: Publish only successful persistence

**Interfaces:** Preserve `saveReport(_ report: DailyReport) -> Bool` at callers during repair; build a candidate collection, persist it, and publish only on success. Apply the same principle to corrections, settings, events, and manifests where durable state is represented as saved.

- [x] Add `failedReportSaveDoesNotPublishReflection` and `retryReportSavePreservesDraft`. Assert the report collection, reflected status, and last successful revision do not advance on failure.
- [x] Add a correction/settings failure test so visible successful preferences cannot diverge silently from disk.
- [x] Implement staged writes and explicit unsaved/error UI. Do not clear a draft after rejection.
- [x] Verify successful retry produces one report revision, not duplicates.
- [x] Run the runner and a synthetic obstructed-store runtime scenario.

### Task C: Make Settings responsive and reproduce the symptom safely

**Interfaces:** Replace synchronous discovery at the view boundary with a cancellable asynchronous operation. Proposed `discover() async -> [AnalysisAgentStatus]` runs process work away from the main actor and publishes results on it. Inject a controllable fake runner.

- [x] Write tests for delayed, hung, unavailable, and canceled agents. A timeout yields `unknown`, not ready or not installed.
- [x] Show Settings immediately with a loading/checking status; coalesce refreshes and avoid repeated processes on every appearance.
- [x] Add the Settings scene and entry-point behavior in plan 03 with macOS availability handling.
- [x] In a temporary fixture, use a deliberately slow fake status runner. Verify the Settings window accepts tab/focus/close while discovery remains pending.
- [x] Record whether the user's failure is reproduced in an authorized non-private launch context. Do not declare a root cause merely because this repair improves responsiveness.

### Task D: Correct analysis payload and status honesty

**Interfaces:** The later `ContextEnvelope` in plan 04 includes observations and corrections separately. For the current narrow repair, extend the input builder with `corrections: [AttributionCorrection]` without changing observations.

- [x] Add a payload test asserting the original observation and explicit correction are both serialized and labeled.
- [x] Add ready-before-run, completed, restored, canceled, and failed-state tests. A failed/canceled request may already have transmitted data; copy must not claim nothing was sent.
- [x] Make parent views observe the published operation state directly.
- [x] Verify restored results show their run date and do not imply a new request occurred.
- [x] Run tests with a fake process runner only; no real AI invocation is needed for this proof.

### Task E: Repair draft, import, and navigation feedback

- [x] Add import-completes-during-edit and navigate-away-and-back tests. Preserve draft text and mark context changes; do not silently replace a question being answered.
- [x] Add aggregate import results keyed by source; filter eligible sources before scheduling. Verify disabled/unverified sources remain unread and each outcome is retained.
- [x] Test event-write failure followed by manifest handling. A manifest must not claim a successful durable import when its event write failed; retain a retryable outcome and accurate coverage.
- [x] Add a filtered-no-matches state with a clear-filter action, distinct from an empty store.
- [x] Correct benchmark IDs/paths to unique stable synthetic identities; assert uniqueness before accepting timings.
- [x] Validate A12 individually and document actual outcomes. If the new primary workflow removes a legacy surface, preserve access to stored user content and test its migration rather than rebuilding unused UI.

## 6. Completion gate

The repair milestone passes only when corrupt stores are protected, failed saves remain unsaved, Settings is responsive under delayed discovery, corrections reach analysis, drafts survive context changes, and the test fixture uses representative identities. Passing helper tests alone does not close native interaction findings.

Record each finding as fixed with proof, still open, or superseded with a migration explanation. Keep unresolved Settings reproduction separate from the confirmed code defects.
