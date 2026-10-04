# Daily reflection implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` for authorized native execution, or `superpowers:subagent-driven-development` when subagent execution is explicitly authorized. Execute task by task using checkbox tracking. Read plans 04–05; AI generation requires explicit configuration and invocation. Reminders are optional local behavior. Do not commit automatically.

**Goal:** Ask one meaningful end-of-day question that clarifies the user's reasoning and improves Reflect's understanding of their growth.\
**Architecture:** Persist one active primary question per local day with a stable context basis, keep answer drafts separate from saved revisions, and feed labeled self-reports into later interpretation. Separate reminder delivery from provider invocation.\
**Tech stack:** Swift, SwiftUI, Foundation Calendar, Codable persistence; system UserNotifications only for separately enabled reminders.\
**Spec:** [01](01-product-vision-and-requirements.md), requirements R05–R09 and R13–R15; contracts in [04](04-architecture-and-technology-plan.md).

## Global constraints

Spec section 9 applies in full. Exactly one active primary question belongs to a persisted day. Do not read histories or invoke an agent automatically at midnight or notification time. Preserve historical report answers; all tests use synthetic temporary stores and a controllable clock.

## Review focus

1. A late import must not replace the question being answered or destroy its draft.
2. Midnight, timezone changes, sleep/wake, and repeated reminder delivery must not create duplicate questions.
3. Missing or agent-only evidence must not produce a question that falsely attributes a decision to the user.
4. Failed answer writes must leave the draft available and the day unreflected on disk.
5. One explanation must not be treated as independently verified competence or a reason for automatic grading.

## 1. Purpose and difference from current behavior

Current `ReportGenerator` produces generic deterministic prompts about attention, tool suggestions, and sometimes commits. They are useful fallback scaffolding, but they do not select the day's most important uncertainty or reliably tailor the question to the user's contribution.

The new question should help Reflect understand what the user did and why. It is not a requirement to write a daily report, review every event, or complete a multi-question exam. The user should be able to answer briefly and receive a useful interpretation without being buried in counts or forms.

## 2. Question selection

Use the day's approved work episodes, corrections, prior unresolved understanding, and explicit goals when known. Candidate uncertainties may concern a tradeoff, debugging hypothesis, validation choice, delegated decision, or transfer of an earlier concept.

Prioritize:

1. A consequential uncertainty about the user's reasoning or contribution.
2. A topic with enough contextual support to ask fairly.
3. A question the user can answer from their actual experience.
4. A useful connection to recurring growth, without repeating the same generic question every day.

Do not choose solely by transcript length, number of errors, commit volume, or the most impressive agent-generated code. Do not ask about an action merely because a tool performed it.

Proposed question record: `DailyQuestion` from plan 04, including text, reason, supporting IDs, basis/generation versions, local-day identity, and status. One candidate is selected as the active primary question. Optional continued conversation after answering is allowed, but the app does not impose several mandatory prompts.

## 3. Question quality

A tailored question must:

- Refer to a supported decision or uncertainty from that day.
- Ask for one focused explanation rather than several unrelated answers.
- Avoid presuming authorship, competence, or intent that has not been established.
- Use plain English without unnecessary implementation jargon.
- Be answerable in a few sentences, while allowing a longer answer.
- Store a short reason for asking, available when the user wants it.

Fictional examples for design/testing only:

| Observed situation | Useful question | What it clarifies |
| --- | --- | --- |
| A transaction was introduced, but decision ownership is unclear. | “The session introduced a transaction around several writes. What did you understand it was intended to protect against?” | Understanding without asserting the user designed it. |
| The user explicitly rejected one caching option. | “What tradeoff made you reject the caching option today?” | Attributable design judgment. |
| An agent fixed a bug and the user chose a specific verification check. | “What did your verification check rule out after the fix?” | Whether verification was meaningful. |
| A previously studied concept appears in a new decision. | “What helped you recognize that the earlier concept applied here?” | Learning transfer. |

Avoid “What did you learn today?” as the default personalized output when concrete context exists. If evidence is absent, do not fabricate a task or pretend a generic question is personalized.

## 4. End-of-day timing and explicit invocation

The desired experience is an end-of-day question. No preferred time or notification behavior was decided in the conversation.

Proposed first release behavior:

- Keep the daily reflection entry available in the app.
- Prepare the tailored question through an explicit configured analysis action, or as an explicitly requested part of a conversation.
- Reuse a previously prepared question at the day's chosen reflection time without invoking the provider again.
- If no question is prepared, offer “Prepare today's question” when the user opens the reflection entry.
- An optional local reminder can open that entry. Enabling a reminder grants notification permission only, not automatic AI/network permission.
- If AI is disabled or context is unavailable, offer a clearly labeled general reflection or manual explanation; it does not support a confident competence conclusion.

Unattended nightly AI generation is not assumed under the present explicit-invocation instruction. If the owner later wants it, define a separate standing-authorization policy and revise the permission boundary explicitly. Do not smuggle it in as a scheduling detail.

## 5. Day identity and lifecycle

Use `LocalDay` with the calendar and timezone recorded at creation. A later timezone change does not silently reassign an existing question or answer. New questions use the current local day; old entries retain their original meaning.

Question lifecycle:

1. No question prepared.
2. Preparing through explicit invocation.
3. Prepared and available.
4. Answer draft in progress.
5. Answer saved.
6. Optional interpretation of the answer through explicit invocation.

If new evidence arrives, mark the basis as changed. Preserve the active question/draft. Before an answer is saved, the user may explicitly replace the question; preserve the replaced record and references. After answering, additional context belongs in a follow-up, not a silent rewrite of the original daily question.

Repeated preparation/reminder requests must be idempotent for the active day/revision. A skipped day is unanswered, not negative growth. Late answers belong to the original question/day. Reminders after sleep should coalesce rather than flood the user.

## 6. Answer handling and feedback

Save answers as user content with question ID, local day, revision, and time. Keep draft text outside persisted completion state. Failed saves retain drafts and show an unsaved/retry state; a reflected badge appears only after successful durable persistence.

Reflect may use an answer to clarify intention or a tentative understanding. It should explain when the answer changes its view. Contradictions between an answer and observed actions remain distinct; neither is erased to force agreement.

Do not automatically penalize imperfect wording, language fluency, missed days, or short answers. Do not treat a polished explanation copied from an agent as proof of independent understanding. Ask a useful later follow-up when needed rather than inventing certainty.

If a next step emerges, store it as proposed, accepted, attempted, or completed with the user's status and any observed outcome. Merely suggesting a task does not mean the user made progress.

## 7. Reminder and notification behavior

Optional implementation details needing review:

- User-selected local reflection time, with reminders off initially.
- Permission request only when the user enables the feature.
- Notification content that does not expose private session/project text on a lock screen.
- One notification per relevant day/revision; cancellation when disabled or already handled.
- Respect system Focus/notification behavior and avoid repeatedly prompting after denial.
- No background collector, launch agent, or scheduler installation by default.

No reminder or automation is created by writing this plan.

## 8. Files and interfaces

Create `Models/LocalDay.swift`, `Models/Intelligence/DailyQuestion.swift`, `DailyReflection.swift`; `Services/Reflection/DailyQuestionPolicy.swift`, `DailyQuestionService.swift`, `DailyReminderService.swift`; and `Stores/DailyReflectionStore.swift`.

Adapt `ReflectionDraftModel.swift`, `ReflectionComposerView.swift`, `TodayView.swift`, and `ReportGenerator.swift` only as needed for migration and replacement. Preserve old multi-question answers as historical user content; do not drop answers because the new design asks one primary question.

**Interfaces:** `DailyQuestionPreparing.prepare(for:context:)` returns a referenced question for the requested day. `DailyReflectionStore.saveAnswer(questionID: String, text: String) async throws -> DailyReflection` persists a new answer revision before publishing saved state. `DailyReminderService` schedules/cancels local reminders only and has no provider dependency.

Tests: `DailyQuestionPolicyTests.swift`, `DailyReflectionPersistenceTests.swift`, `DailyBoundaryTests.swift`, and `DailyReminderTests.swift`, registered in `RunnerMain.swift`.

## 9. Tasks

### Task D1: One-question policy and context basis

- [ ] Test tailored decision selection, agent-only uncertainty, absent evidence, repeated themes, and unknown attribution.
- [ ] Assert one active primary question per `LocalDay`, with supporting IDs present in the envelope for tailored claims.
- [ ] Implement candidate selection and output validation; reject fabricated task names and multi-prompt surveys.
- [ ] Verify question preparation is reachable only from an explicit configured invocation.
- [ ] Run `swift run reflect-test-runner` with a fake question generator.

### Task D2: Durable draft and answer flow

- [ ] Test failed save, retry, route change, relaunch, revised answer, late import, and explicit question replacement.
- [ ] Implement stable question/answer records and persist-before-publish saved state.
- [ ] Migrate existing answers without fabricating a question-to-session relationship.
- [ ] Integrate the focused native answer surface and optional continued chat.
- [ ] Verify the synthetic runtime journey preserves a draft across Settings and conversation navigation.

### Task D3: Honest feedback into assessment

- [ ] Test that saved answers enter context as self-reports, with corrections and references.
- [ ] Test a strong explanation without independent evidence; confidence must not become an unsupported demonstration claim.
- [ ] Link explicit follow-up analysis to a new snapshot rather than replacing historical observations.
- [ ] Verify a missed reflection day does not reduce ability or reset prior learning.

### Task D4: Optional local reminder

- [ ] Confirm time/notification preference before enabling product reminders.
- [ ] Test notification denial, sleep/wake, midnight, timezone changes, duplicate triggers, and disabling.
- [ ] Verify the reminder path makes zero provider calls and exposes no private content.
- [ ] Record notification runtime proof separately from clock-policy unit tests.

## 10. Completion gate

The daily loop produces one fair, relevant question; keeps its context and answer durable; incorporates the explanation honestly; and works without compulsory extra questions, evidence browsing, or hidden nightly AI requests.
