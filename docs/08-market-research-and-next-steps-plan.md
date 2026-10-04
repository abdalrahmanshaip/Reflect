# Market research and next steps implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` for authorized native execution, or `superpowers:subagent-driven-development` when subagent execution is explicitly authorized. Execute task by task using checkbox tracking. Read plans 04–06 and keep public research separate from personal assessment. Real requests require explicit configuration and invocation. Do not commit automatically.

**Goal:** Let the user ask about opportunities and improvement naturally, with current public requirements and grounded personal comparisons.\
**Architecture:** Resolve context at query time, fetch bounded public research, then compare those requirements with labeled personal claims locally or through the explicitly configured analysis boundary. Store actionable next steps independently from evidence of completion.\
**Tech stack:** Swift, Foundation/URLSession for an eventual supported configured research transport, Codable, existing intelligence services; no third-party packages.\
**Spec:** [01](01-product-vision-and-requirements.md), requirements R04, R09–R13.

## Global constraints

Spec section 9 applies. No fixed market or role is required during setup. Public searches must not include raw transcripts, private repository names/paths, credentials, or other unnecessary personal details. Current code's no-external-services analysis instruction remains in force until a separately designed research capability is implemented.

## Review focus

1. A broad question must not quietly become a verdict about one geography or seniority.
2. Sparse, old, or conflicting job postings must not support an exact universal market ranking.
3. Weak personal coverage must not be reported as failure to meet a requirement.
4. A research provider failure must not be filled with plausible fabricated hiring facts or citations.
5. Recommended work must not be counted as completed growth merely because the assistant proposed it.

## 1. Why market context belongs in conversation

The earlier suggestion of choosing a role and hiring market up front was superseded. The user wants Reflect to infer a work profile and allow questions like a conversational assistant.

Context can emerge in a question, a follow-up, or an explicit aspiration. A query about “senior backend roles in Germany,” for example, supplies role, level, and geography directly. A broad query such as “what jobs might fit me?” should explore plausible paths from demonstrated work, explaining assumptions rather than blocking on an onboarding form.

Distinguish employment market, technical specialty, company environment, and the user's desired direction. The work profile is not necessarily the desired career. Remember explicit goals when the user states them, but do not turn a one-time exploratory query into a permanent identity.

## 2. Context-resolution policy

When information is missing:

1. Use relevant explicit context already stated in the conversation or stored aspirations.
2. If several useful possibilities remain, present them and state the scope of the comparison.
3. Make a labeled assumption if it is low consequence and easy to correct.
4. Ask one focused follow-up only when the missing detail materially changes the answer.

Do not repeatedly ask “what is your market?” after the user has rejected static setup. A clarification must explain why the detail matters in this particular query.

Personal progress and next-step questions can work without public market research. An unavailable research provider must not disable the daily question or private progress conversation.

## 3. Public research capability

Current Reflect analysis is deliberately restricted to supplied evidence and disallows tools/external services. Do not remove that boundary globally merely to add market research.

Implement a separate `PublicMarketResearching` service with supported configuration and an explicit invocation. Choose the research transport/provider only after verifying current official documentation, availability, privacy, pricing where relevant, and compatibility with system-framework-only implementation. No provider was selected in the discussion.

Proposed bounded initial request limits, subject to review:

- At most three public searches per user research request.
- At most eight selected source documents per comparison.
- Prefer actual employer career postings and official occupational/professional information.
- Record date/location/role relevance, posting date where available, and retrieval time.

These limits are engineering starting points, not proof of representative sampling. Explain the limitations of the sources actually collected. Do not claim to know the whole market from a few listings.

## 4. Separation of personal and public data

Create generic public queries from the user's requested role/market context, such as a specialty, location, and level. Keep raw personal work history out of search requests.

After retrieving public requirements, compare them with approved personal context. If the configured analysis agent receives both, show the applicable transmission scope and use the same explicit invocation boundary as private chat. Store public-source provenance separately from local evidence references.

Treat web pages as untrusted source material. Their embedded instructions cannot alter privacy scope or grant tools. Source URLs must be actual retrieved documents; never invent citations from plausible employer names.

## 5. Readiness comparison

Use requirement-by-requirement reasoning:

| Comparison outcome | Meaning |
| --- | --- |
| Demonstrated match | Relevant personal evidence supports the requirement within a stated scope. |
| Partial or tentative match | Some support exists but complexity, independence, or breadth is not established. |
| Unknown | The app lacks appropriate evidence; this is not proof of inability. |
| Observed development need | Evidence supports a specific limitation, explained with uncertainty and context. |
| Outside Reflect's evidence | Hiring considerations such as interview performance or interpersonal behavior may not be observable in imported sessions. |

Reflect can identify plausible roles and useful development priorities. It cannot guarantee hiring outcomes or reduce the user to a universal rank. Job-title usage varies between employers; avoid comparing titles as if they were a uniform scale.

A good answer explains the target context, strongest supported fit, material unknowns, public source basis/date, and a next step. The user should not need to open an evidence table to understand the conclusion.

## 6. Freshness and unavailable research

Label research with its retrieval date and relevant posting/publication dates. Cached requirements remain dated; a new request for a current comparison must refresh or clearly state that fresh research is unavailable.

If sources are old, unavailable, thin, paywalled, contradictory, or regionally mismatched, state the limitation. Offer an evidence-based personal assessment or compare a job description the user explicitly supplies, labeled as supplied material. Do not pretend this is live market research.

When no research capability is configured, personal history can still support role exploration and general preparation advice. Time-sensitive demand/hiring claims remain unavailable until sourced.

## 7. Next-step quality

A next step should connect to a stated goal or demonstrated uncertainty. Proposed structure from `NextStep`:

- A concrete task or experiment.
- Why it matters for the current question.
- The dimension or requirement it exercises.
- A bounded scope and recognizable completion condition.
- Optional evidence the user could bring back.
- Status: proposed, accepted, attempted, completed, or declined.

Prefer one priority when the user asks “what next?” Provide a broader plan only when requested. Do not generate an endless study checklist disconnected from current work.

Fictional example: if transaction reasoning is uncertain, suggest implementing and explaining a small multi-write failure scenario, predicting the result before testing it. Completion requires an explanation and observed behavior, not merely a checked box or copied code.

When the user reports completion, retain that as self-report until supporting work is available. A declined suggestion is a preference signal, not negative progress. Follow-up should help evaluate the outcome, not enforce a streak.

## 8. Files and interfaces

Create the Research models and `NextStep` from plan 04; `Services/Research/MarketResearchService.swift`, `MarketComparisonService.swift`, `NextStepBuilder.swift`; and a focused research configuration section in Settings once a provider is chosen.

**Interfaces:** `PublicMarketResearching.research(_:)` returns `MarketResearchResult` containing public sources/requirements/limitations only. `MarketComparisonService` consumes that result plus validated profile/assessment claims and coverage; its output is a `ConversationResponse` with sourced comparison claims and optional `NextStep` records.

Store next steps and public research records through `IntelligencePersistenceController`. Keep pending research state in `ConversationStore`, tied to its request ID. Do not bolt a broad web-capable agent onto every private question.

Tests: `MarketContextTests.swift`, `PublicResearchPrivacyTests.swift`, `MarketComparisonTests.swift`, and `NextStepTests.swift`, registered in `RunnerMain.swift`.

## 9. Tasks

### Task M1: Query-time scope without mandatory setup

- [ ] Test broad role exploration, fully specified queries, one-time exploratory markets, inherited explicit aspirations, and missing high-impact context.
- [ ] Implement request scope and assumption recording; profile inference must not overwrite the user's chosen goal.
- [ ] Verify ordinary progress chat works without role/market fields.

### Task M2: Public-only research transport

- [ ] Select and document the supported transport using current primary documentation; keep unsupported capability visibly unavailable.
- [ ] Test that outgoing public queries contain only intended generic terms, using synthetic private names/tokens as exclusion checks.
- [ ] Test source provenance, bad URLs, conflicting dates, provider errors, empty results, cache dates, and request limits.
- [ ] Implement explicit configured research invocation using system networking only.
- [ ] Verify real retrieval only when separately invoked; automated tests use fake responses.

### Task M3: Grounded comparison

- [ ] Test demonstrated, tentative, unknown, and observed-need outcomes against fictional postings.
- [ ] Reject invented source URLs, exact unsupported percentiles, unsourced market claims, and unknown-equals-failure reasoning.
- [ ] Implement comparison with public and personal provenance kept separate.
- [ ] Verify the answer remains readable and useful without evidence browsing.

### Task M4: Next steps and outcome follow-up

- [ ] Test proposed/accepted/attempted/completed/declined state transitions and failed writes.
- [ ] Implement a concrete completion condition and link to the relevant claim or requirement.
- [ ] Verify suggestions alone do not advance the profile; self-reported completion remains labeled.
- [ ] Follow up within conversation and daily reflection when useful, without mandatory reminders or gamification.

## 10. Completion gate

A user can ask about opportunities with query-time context, receive dated public-source support or an explicit unavailable state, understand personal fit and uncertainty, and choose a practical next step. No fixed market onboarding, raw-history search transmission, fabricated ranking, or assumed completion is introduced.
