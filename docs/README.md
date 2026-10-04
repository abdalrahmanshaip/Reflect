# Reflect planning documents

Written 2 October 2026 from the product discussion and the source/desktop audit conducted in this conversation.

Reflect's agreed purpose is to help its owner understand whether they are growing as an engineer, where they stand, and what to do next. The main experience is a conversation informed by approved work history, supported by an evolving profile and one meaningful daily question.

## Status and authority

**Implementation checkpoint:** start at [CONTINUE-HERE.md](CONTINUE-HERE.md) for the current incomplete state and exact restart task. Detailed historical evidence is in [implementation-progress.md](implementation-progress.md).

- The product direction was accepted in conversation. These documents record it comprehensively.
- Implementation details, new type names, UI layouts, performance targets, and optional features are proposals for review, unless explicitly identified as existing behavior or an agreed requirement.
- This documentation task changes no application code, runs no personal imports or AI requests, and makes no commit.
- `AGENTS.md` remains the implementation constraint. New plans do not authorize reading private histories, installing dependencies, invoking agents, changing the supported platform, or publishing a release.
- The latest conversation supersedes earlier ideas that required a fixed Software Engineer role, a fixed hiring market, or evidence browsing as the primary experience.
- Existing `PRIVACY.md` and `INTEGRATIONS.md` are preserved. They describe earlier implementation snapshots; provider behavior and source compatibility must be reconciled with current code before a release.

## Reading order

| Document | Purpose |
| --- | --- |
| [01 — Product vision and requirements](01-product-vision-and-requirements.md) | Source of truth for purpose, agreed behavior, scope, and success criteria. |
| [02 — Current-state audit and repair](02-current-state-audit-and-repair-plan.md) | What currently causes the unfinished impression; verified defects, suspected causes, and repair tasks. |
| [03 — Native macOS experience](03-native-macos-experience-plan.md) | Application shell, visual direction, Settings, commands, focus, cursor behavior, and desktop acceptance. |
| [04 — Architecture and technology](04-architecture-and-technology-plan.md) | Framework comparison, recommended stack, component boundaries, shared contracts, migration, and rewrite criteria. |
| [05 — Evidence and personal memory](05-evidence-and-personal-memory-plan.md) | Approved collection, richer session context, corrections, retrieval, durable memory, and privacy. |
| [06 — AI conversation and growth assessment](06-ai-conversation-and-growth-assessment-plan.md) | Chat, agent integration, profile inference, honest assessment, longitudinal comparison, and output validation. |
| [07 — Daily reflection](07-daily-reflection-plan.md) | One tailored question, question selection, answers, reminders, daily boundaries, and learning feedback. |
| [08 — Market research and next steps](08-market-research-and-next-steps-plan.md) | Query-time market context, fresh public research, readiness comparisons, and actionable development steps. |
| [09 — Delivery and validation](09-delivery-and-validation-plan.md) | Dependency order, milestones, synthetic test strategy, performance, packaging, and release gates. |
| [10 — Conversation coverage and decisions](10-conversation-coverage-and-decisions.md) | Traceability for every substantive topic, superseded proposals, and unresolved choices. |

Read 01 and 10 before choosing a subsystem. Read 04 before implementing any interface shared by multiple subsystems. Use 09 to sequence work; do not treat the numerical document order as the execution order.

## How to execute a plan later

1. Review the selected plan and its prerequisites against the current checkout.
2. Preserve existing uncommitted work. Establish the intended baseline before applying changes.
3. Work through one independently verifiable deliverable at a time.
4. Keep all personal data in Reflect's Application Support store; use synthetic temporary fixtures for tests and visual checks.
5. Record source, test, runtime, and packaging proof separately. A passing test runner does not establish a polished desktop experience or an accurate career assessment.
6. Do not commit automatically. Independent review and explicit orchestration govern commits.

## What this set deliberately leaves open

Exact visual composition, supported source-format expansion, the research provider, storage indexing strategy, reminder preferences, and distribution tooling need implementation-time decisions. Each has a concrete decision task in the relevant plan rather than an implicit promise that the feature already exists.

The core direction is settled: conversation first; profile inferred and correctable; no mandatory role/market setup; one useful daily question; honest progress assessment; private evidence in the background; a polished native Mac experience.
