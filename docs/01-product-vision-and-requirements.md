# Reflect product vision and requirements

**Date:** 2 October 2026\
**Status:** Accepted product direction recorded for review; technical implementation proposals are in the linked plans.\
**Owner:** Reflect's user and product owner.\
**Scope:** Personal engineering growth on macOS, informed by the user's approved work with AI tools.

## 1. The problem Reflect must solve

The user wants to know whether their actual engineering ability is improving while working with AI agents. Finished code, activity counts, and convincing agent explanations can obscure the distinction between producing an outcome and understanding how that outcome was achieved.

Reflect should help answer:

1. Am I actually improving?
2. What can I currently demonstrate, and what remains uncertain?
3. Which kinds of engineering work fit my demonstrated strengths?
4. Where might I stand against the requirements of opportunities I care about?
5. What is the most useful next step?

The application should be useful even when the user does not know their preferred job title or hiring market. The initial mention of Software Engineer expresses engineering interest; it is not a permanent classification or an onboarding requirement.

## 2. Why the existing experience feels weak

The user described Reflect as feeling like a note rather than a complete Mac application, with weak visual quality and uncertain interaction. They specifically reported sidebar Settings not opening and questioned why clickable navigation items did not change to a pointing hand.

The audit found a native SwiftUI application, but its current information architecture emphasizes counts, reports, generic questions, and loosely connected reading screens. Its desktop command integration and feedback are incomplete. Some save/load and analysis states can be misleading. These are product and engineering problems, rather than proof that Swift is a poor language.

The emotional concern matters: the user is open to replacing substantial code because the idea matters more than preserving the existing implementation. The planning response should restore clarity by describing a useful product and a verifiable path, rather than defending the current screens or adding decorative styling alone.

## 3. Agreed product definition

Reflect is a native macOS application built around an ongoing conversation that understands the user's approved work over time. It maintains an evolving, correctable profile, compares progress using a consistent basis, and asks one meaningful question about each day's work.

Its distinctive value comes from continuity: it can relate a present decision to earlier decisions, recognize a recurring difficulty, incorporate the user's explanation, and follow up on a previous next step. It must earn these conclusions from available evidence rather than manufacture encouragement.

## 4. Primary experience

### Conversation

The user asks in ordinary language, without selecting a rigid assessment form. Example intents include progress, strengths, uncertainty, reliance on agents, possible roles, market questions, and next steps. These examples define supported intentions, not a fixed list of commands.

Reflect retrieves relevant approved history and answers with a clear conclusion, a brief reason, the material uncertainty, and a practical action when appropriate. It should remember the context of a follow-up so the user does not need to repeat their background.

### Evolving understanding

Reflect can infer the kind of work the user appears to do. An inferred full-stack profile, for example, should be presented as a current interpretation of observed work. It cannot establish a formal job title, desired career, or seniority merely from the frequency of technologies in transcripts.

The user can correct the profile conversationally. Explicitly stated ambitions are stored separately from inferred work patterns. Multiple possible role fits can coexist, and profiles change as evidence develops.

### One daily question

At the end of a day, Reflect should ask one question tied to meaningful work from that day. Its purpose is to clarify reasoning, contribution, judgment, or understanding that the collected record cannot establish.

The question is a focused invitation, not a generic daily survey, quiz score, or requirement to answer several prompts. A user's answer can improve or correct Reflect's understanding. The answer is a self-report, not automatic proof that a claimed skill was independently demonstrated.

### Progress and next steps

Reflect should explain what appears to have changed over time, how that conclusion was reached, and where the comparison is incomplete. A next step should be an actionable experiment, practice task, or work habit with a recognizable completion condition.

### Market questions on demand

There is no mandatory market during setup. Context such as geography, specialty, company type, or seniority is introduced when the question requires it. Reflect may proceed with an explicit assumption or ask one useful follow-up if that missing detail materially changes the answer.

Personal work history describes the user. Current public job requirements describe opportunities. Market comparisons require both and must acknowledge sampling and coverage limits.

## 5. Evidence stays in the background

The user explicitly does not want to browse collected evidence as the main activity. Therefore:

- Do not make raw event tables, import counts, attribution charts, or evidence selection the main home screen.
- Provide a brief natural explanation of important conclusions.
- Allow an optional explanation or supporting context when the user asks why, corrects a conclusion, or troubleshoots a source.
- Keep Sources and diagnostic record tools available through secondary navigation or Settings.
- Automatic selection of relevant already-approved context should replace repetitive record-picking for ordinary chat. The active scope must remain understandable and controllable.

Background evidence is essential for reliable answers even when its storage and inspection interface are secondary.

## 6. The four distinctions the product must preserve

| Distinction | Product consequence |
| --- | --- |
| Actual work versus intended career | Infer current work patterns; learn ambitions from the user when relevant. |
| Exposure versus understanding | A transaction in an agent transcript does not prove the user's transaction knowledge. Ask about the decision when useful. |
| Fluent conversation versus measurable continuity | Store dated, attributable interpretations and compare with a consistent rubric; do not regenerate an unrelated verdict each day. |
| Personal history versus market conditions | Use current public research for market claims; do not derive hiring demand from personal logs. |

## 7. Native macOS quality

The user's references are WhatsApp on Mac, Cursor, and Dia. The qualities they value are uniqueness, elegance, visual restraint, coherent structure, and a luxurious feeling. These are taste references, not claims that the products share a framework or permission to copy their branding.

Reflect should combine familiar navigation, a capable conversational workspace, and calm chrome. Real Mac quality also requires functional Settings, application menus, keyboard access, focus, window behavior, accessibility, durable state, and responsive background work.

The normal macOS arrow pointer is appropriate for native controls. Custom surfaces still need clear interactive roles and visible selection, hover, pressed, and disabled states. Blanket hand cursors are not the definition of native quality.

## 8. Requirements

| ID | Requirement | Acceptance condition |
| --- | --- | --- |
| R01 | Explain growth using approved work history. | A response distinguishes demonstrated change, uncertainty, and the relevant comparison period. |
| R02 | Make conversation the main experience. | A user can ask a follow-up without finding and selecting raw records again. |
| R03 | Infer a revisable work profile. | Profile claims carry their basis and can be corrected without choosing a static role. |
| R04 | Avoid mandatory role or market onboarding. | Setup and ordinary progress chat work without either field. |
| R05 | Ask one meaningful daily question. | One primary question is associated with a local day, context, and a reason for asking. |
| R06 | Use daily answers to refine understanding. | Answers and their revisions remain user content; derived interpretations link back to them. |
| R07 | Keep evidence secondary. | The default workflow is conversation/reflection; diagnostics are optional. |
| R08 | Distinguish user contribution from agent output. | No authorship or competence claim is inferred from a generated artifact or commit metadata alone. |
| R09 | Preserve longitudinal comparability. | Assessment snapshots record time, coverage, rubric/prompt/model versions, and corrections. |
| R10 | Research markets when needed. | Time-sensitive market claims have public sources and retrieval dates, or are explicitly unavailable. |
| R11 | Offer concrete next steps. | A recommendation states the reason, a task, and a completion condition without claiming it was done. |
| R12 | Integrate approved agents on the machine. | A configured, supported agent can be explicitly invoked; missing/authentication/error states are clear. |
| R13 | Keep data private and imports controlled. | No launch-time history read, source mutation, repository leakage, or unapproved transmission occurs. |
| R14 | Be a polished native Mac application. | Settings, commands, keyboard/focus, resize, accessibility, and state restoration work in runtime checks. |
| R15 | Save and load honestly. | Failed reads cannot masquerade as a fresh empty store; failed writes cannot masquerade as saved progress. |
| R16 | Remain open to substantial code replacement. | Keep or replace components based on these requirements and proof, rather than existing screen structure. |

## 9. Global implementation constraints

These apply to every implementation plan:

1. Native SwiftUI macOS app with Swift Package Manager.
2. Only system frameworks; no third-party package/network dependencies. Explicit configured AI or research requests are a separate runtime permission boundary, not a dependency exemption.
3. Current deployment floor is macOS 13; any change is a separate decision. New APIs need availability handling.
4. All UI, reports, settings, questions, and docs in English.
5. Private, untrusted session contents remain only in Reflect's Application Support store. Never put real contents in source, tests, logs, screenshots, or bundled demo data.
6. No real history reads without an explicit real import through the app's adapter. Imports are read-only, opt-in, local, and deduplicated.
7. Observations, inferences, user corrections, and self-reported answers remain distinct.
8. No AI request without explicit configuration and invocation. New API credentials use Keychain; reuse supported CLI authentication without reading credential stores.
9. Missing evidence means unknown or incomplete, never zero ability or automatic regression.
10. Narrow responsibilities: separate models, source adapters, persistence, services, and views. Preserve unrelated dirty work.
11. Tests and visual checks use synthetic temporary fixtures only. No commit is authorized by these plans.

## 10. Scope and boundaries

The first complete release should provide dependable storage, native Settings and shell, richer approved context, a configured conversational agent, correctable profile/assessment memory, and one daily reflection flow. Market research follows behind a separate capability and acceptance gate; an unavailable research service must not prevent personal-growth chat.

Browser/search collection, Cursor database import, notifications, menu-bar utilities, cloud synchronization, mobile support, team dashboards, full autonomous agents, and numeric rankings are not assumed to be implemented. Search/work signals are part of the desired context, but each new source needs its own approved adapter and proof.

A full rewrite is permitted as a possibility. It is not a requirement to discard useful deduplication, privacy boundaries, or persistence models without review. Framework alternatives are documented in plan 04; the current project instructions favor SwiftUI with selective AppKit.

## 11. Success criteria

A useful Reflect session should leave the user with a clearer, defensible understanding of their progress and one practical next action. It should be possible to correct a mistaken interpretation, resume later without losing context, and see a meaningful comparison after additional work.

Assess product success with synthetic task scenarios and, only when separately authorized, private in-app trials. Do not judge success by number of screens, records imported, AI messages, cards, animations, or test cases. Validate trust, relevance, continuity, and native usability.

## 12. Example journey

This is a fictional design example, not an assessment of the user:

1. The owner explicitly imports an approved session.
2. They ask whether their debugging is improving.
3. Reflect compares relevant older and newer sessions, noting whether hypotheses, reproduction, and verification are actually attributable to the owner.
4. It explains a tentative improvement and one uncertainty.
5. At the end of the day, it asks why the owner chose a particular diagnostic check.
6. Their answer becomes a dated self-report and may refine the interpretation.
7. Reflect suggests a bounded debugging exercise and later asks whether it was completed.
8. A future job-readiness question introduces current public requirements without changing the user's permanent identity.

## 13. Plan links

Use [02](02-current-state-audit-and-repair-plan.md) for current defects, [03](03-native-macos-experience-plan.md) for desktop quality, [04](04-architecture-and-technology-plan.md) for shared interfaces, [05](05-evidence-and-personal-memory-plan.md) for context, [06](06-ai-conversation-and-growth-assessment-plan.md) for reasoning and chat, [07](07-daily-reflection-plan.md) for the daily loop, [08](08-market-research-and-next-steps-plan.md) for opportunities, and [09](09-delivery-and-validation-plan.md) for delivery.
