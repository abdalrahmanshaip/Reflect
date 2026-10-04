# Conversation coverage and decision register

**Date:** 2 October 2026\
**Purpose:** Preserve every substantive topic from this conversation, show where it is planned, and prevent earlier proposals from becoming accidental requirements.\
**Status:** A traceability register, not implementation proof.

## 1. Evolution of the discussion

1. The user asked why Reflect feels like a note and an unfinished Mac application, reported weak clickable affordances and broken sidebar Settings, and requested subagent research about Mac conventions and framework alternatives.
2. The audit established that Reflect is already native SwiftUI/SwiftPM. It identified concrete state defects, thin desktop integration, report-heavy composition, and limitations in the tests and runtime proof.
3. The user named WhatsApp on Mac, Cursor, and Dia as excellent references, emphasizing uniqueness, elegance, and a luxurious feeling.
4. The user clarified the core goal: know whether they are growing as a programmer using AI prompts, decisions, chats, searches, and work; ask one meaningful daily question; answer current standing, market position, and next steps; connect with agents on the machine.
5. The user explicitly said they do not want evidence browsing as the primary experience.
6. An earlier proposal asked for a target role and market. The user initially said Software Engineer, then rejected making role/market static and proposed a chat experience with an inferred profile.
7. The debate accepted conversation-first design while distinguishing work from ambition, exposure from understanding, chat fluency from longitudinal assessment, and personal history from current market requirements.
8. The user accepted this direction and asked for comprehensive planning files in `docs`.

## 2. Topic coverage

| Conversation topic | Recorded decision or finding | Main document |
| --- | --- | --- |
| Whether Reflect is a real native Mac application | It already uses native SwiftUI; product/interaction incompleteness explains the weak impression. | 01 §2; 02 §2; 04 §1. |
| “Feels like a note” | Move the primary experience from reports/forms/counts toward a capable conversation and daily reasoning loop. | 01 §4; 03 §2. |
| Poor/elegant/luxurious visual quality | Treat taste as hierarchy, coherence, restraint, identity, and useful interaction, not decoration alone. | 03 §§1–3. |
| WhatsApp reference | Familiar readable conversation structure. | 03 §1. |
| Cursor reference | A capable workspace with context and meaningful actions. | 03 §1. |
| Dia reference | Calm chrome/proportions and clear identity. | 03 §1. |
| Today/This Week/Patterns buttons and cursor | Native arrow is normal; actual affordance, selection, accessible activation, and rendered behavior need verification. | 02 §3; 03 §4. |
| Sidebar Settings failure | Worked in the synthetic build; actual reported failure remains unproven. | 02 §1 and A04–A05. |
| Potential Settings freeze | Sequential synchronous auth discovery on the UI path is a confirmed risk, not a proved root cause. | 02 Task C; 03 §4. |
| Native Settings and Command-comma | Dedicated Settings scene with the same menu/footer behavior and tested OS fallback. | 03 Tasks N2/N4. |
| Stale installed app suspicion | Shared Mach-O UUID did not establish a stale build; differing hashes alone are inconclusive. | 02 §1. |
| Need to check all application behavior | Findings register, remaining runtime gaps, complete validation journey. | 02 §§1–3; 09 §9. |
| Subagent research | Three research lanes covered Mac conventions, framework options, and source defects; findings consolidated in plans. | 02 §1; 04 §1. |
| Language/framework worry | SwiftUI is already a modern declarative framework; tooling does not guarantee design quality. | 04 §§1–2. |
| HTML/CSS/JS versus Next/Tailwind/shadcn analogy | Useful comparison of component/tooling maturity; web frameworks do not automatically supply Mac integration. | 04 §1. |
| Other Mac development approaches | AppKit, Tauri/React, Electron/React, Flutter, MAUI, and React Native macOS compared. | 04 §1. |
| Xcode option | Useful for previews/UI automation/profiling/distribution; can retain SwiftPM modules. | 04 §2. |
| Willingness to replace the whole application | Idea drives keep/replace decisions; a full rewrite remains possible with migration and proof. | 01 §10; 04 §8. |
| Existing uncommitted work | Preserve it; establish a baseline before implementation; no commit authorized. | 09 §1. |
| Why growth is hard to recognize with agents | Completed output can conceal who reasoned or understood. | 01 §1; 06 §§3–4. |
| Prompts and AI conversations | Approved source context must retain meaningful ordered session/turn information. | 05 §§1–3. |
| Decisions and choices | Extract referenced work episodes and assess reasoning/ownership cautiously. | 05 §3; 06 §4. |
| Searches and things worked on | Desired signals; no browser-history import currently implemented, new adapters remain explicit. | 05 §2 and Task E4. |
| One end-of-day question | One primary question per local day, chosen to resolve meaningful uncertainty. | 07 §§2–5. |
| Understand what was done and why | Daily explanation informs subsequent interpretation without becoming automatic proof. | 07 §6. |
| Evidence is not interesting to the user | Evidence stays in the background; scope and explanations remain accessible when useful. | 01 §5; 03 §2. |
| “Where do I stand?” | Dated supported profile/assessment with unknown areas, not a universal rank. | 06 §§3–6. |
| “Where am I positioned in the market?” | Query-time public requirements plus personal context; no static market or guaranteed hiring outcome. | 08 §§1–6. |
| “How can I improve / what is next?” | Concrete bounded next steps with completion conditions and outcome tracking. | 08 §7. |
| Agents on the machine | Supported configured CLI bridge; source import and inference support are separate. | 06 §2. |
| Initial Software Engineer answer | Engineering scope retained; initial role answer does not impose a fixed classification. | 01 §1; 10 §4. |
| Infer role directly from evidence | Infer an evolving work profile, with corrections, uncertainty, and multiple possible fits. | 06 §3. |
| Work profile versus desired direction | Store explicit aspirations separately; do not infer them from recent work volume. | 01 §6; 06 §3. |
| ChatGPT-like chat | Natural follow-ups and relevant approved context, without repetitive raw record selection. | 01 §4; 06 §1. |
| Ask whatever is relevant | Flexible questions; distinguish general advice from personalized conclusions and sourced current facts. | 06 §1; 08 §6. |
| Evidence versus understanding | Agent output or topical exposure does not establish user competence. | 06 §4; 07 §§2–3. |
| Chat alone is insufficient | Durable dated memory and comparable dimensions prevent unrelated daily verdicts. | 06 §5. |
| AI opinions reinforcing themselves | Prior interpretations remain interpretations and cannot become fresh proof. | 05 §3; 06 §§5–6. |
| Current collection is too shallow | Capped excerpts/flat records need richer approved context; no recovery by guessing. | 05 §1. |
| RAG/context research | Contextual chunks, bounded retrieval, and durable memory inform the architecture; no provider dependency mandated. | 05 §10; 06 §11. |
| Current role/market setup rejection | No mandatory static fields; relevant context is resolved when a question needs it. | 08 §2. |
| Request to debate | Preserve the four distinctions and technical limits rather than accepting “the AI knows” without scrutiny. | 01 §6. |
| Privacy and opt-in | Local owned storage, read-only sources, separate transmission and research boundaries. | 01 §9; 05 §4. |
| Malformed storage silently appears empty | Protect originals and surface store health. | 02 Task A. |
| Failed save still marks a day reflected | Persist before publishing saved state; retain drafts. | 02 Task B. |
| Corrections omitted from AI payload | Serialize observations and corrections separately. | 02 Task D; 05 Task E3. |
| Misleading analysis/privacy status | Track actual lifecycle and possible transmission, including restored results. | 02 Task D; 06 §7. |
| Questions stale after import | Preserve question/draft and flag changed basis. | 02 Task E; 07 §5. |
| Import-all feedback | Eligible sources and aggregate per-source outcomes; no bypass established. | 02 Task E. |
| Empty filters mistaken for first run | Distinct no-matches state and clear filters. | 02 Task E. |
| Tests do not prove real UI | Separate helper/unit proof from activation/focus/VoiceOver proof. | 03 Task N4; 09 §5. |
| Duplicate performance IDs | Fix identity fixture before accepting representative timings. | 02 Task E; 09 §7. |
| Weekly future navigation, Show all scope, detail scroll, About, English dates | Verify individually; preserve content if legacy screens are replaced. | 02 A12 and Task E. |
| Native navigation/state continuity | Central durable state; restore drafts, route, and useful position. | 03 §§4–6. |
| Build/test/package distinction | CLT authoritative runner, synthetic UI proof, packaging/signing separate. | 09 §§4–5 and M8. |
| Request for comprehensive `docs` plans | Linked vision, subsystem plans, delivery gates, and this coverage register. | `docs/README.md` and documents 01–10. |

Section references describe this document set; use the linked reading guide to locate each file.

## 3. Accepted product decisions

- Conversation is the primary experience.
- Reflect's purpose is personal engineering growth, current standing, and useful next steps.
- Approved AI prompts/chats/decisions/work form the contextual basis; desired search signals need verified adapters.
- Role is inferred as a correctable, evolving work profile; aspirations are learned when relevant.
- No fixed role or market is required at setup.
- One meaningful daily question clarifies the day's reasoning and contribution.
- Evidence is secondary; useful answers and explanations matter more than browsing records.
- Progress requires historical continuity and a consistent assessment basis.
- Agent output is not automatic proof of human authorship or understanding.
- Current market comparisons need public research and uncertainty.
- The native application should be elegant, coherent, responsive, and dependable.
- The idea can justify extensive code replacement.

## 4. Superseded or rejected proposals

| Earlier proposal | Current position |
| --- | --- |
| Choose Software Engineer as a permanent target role. | The user initially named it, then explicitly rejected static role selection. Engineering remains the product domain; work profile can evolve. |
| Choose a hiring market before useful assessment. | No mandatory market. Introduce context only when relevant to a question. |
| Make evidence investigation the main product loop. | Evidence remains supporting infrastructure; conversation and the daily question lead. |
| Treat existing report-first designs as the final target. | They are reference/history. The accepted conversation-first direction governs new composition. |
| A new framework will automatically make the application excellent. | Quality depends on product usefulness, design, state, native behavior, and verification. |
| Every clickable control needs a hand pointer. | Native pointer meaning and clear interaction semantics govern the treatment. |
| Collected activity lets AI know competence directly. | It supports tentative inference; context, attribution, corrections, and daily explanation remain necessary. |
| A successful core test suite proves polished Mac behavior. | Runtime task completion, accessibility, and adverse-state checks are separate proof tiers. |

## 5. Open decisions with owners and resolution gates

These are explicitly open technical/product choices, not requirements to ask the user for a static role or market.

| Choice | Proposed position | Resolution task |
| --- | --- | --- |
| Exact visual composition/navigation labels | Calm conversation workspace with compact reflection/progress access. | 03 N1; review synthetic concepts. |
| Multiple main windows | Begin with a coherent main-window experience; define state ownership before expansion. | 03 N2/N4. |
| Reminder time and notification preference | Optional, off initially; no time assumed. | 07 D4. |
| Unattended question generation | Not authorized by present explicit-invocation rule. | Separate policy decision if later requested; 07 §4. |
| Source retention depth | Enough approved context for meaningful interpretation, with separate small display previews. | 05 E1/E2. |
| Automatic collection cadence | No background read assumed; explicit import remains current boundary. | Separate opt-in collector design if requested. |
| Cursor/VS Code/search format expansion | Unverified capability stays unavailable. | 05 E4. |
| Retrieval/index implementation | Local transparent retrieval first; system SQLite/embeddings only if justified. | 04 AR5; 05 E3. |
| Exact shared schema/budget values | Contracts and initial limits are proposals requiring consistency review. | M1 in 09. |
| Assessment rubric | Six stable qualitative dimensions proposed; no numeric rank. | 06 C3; M4. |
| Agent selection/model | Existing supported Codex/Claude CLI options; configure explicitly. | 06 C4. |
| Market research transport/provider | No provider selected; system networking and explicit capability required. | 08 M2. |
| Xcode application target | Optional when a specific tooling/distribution need justifies it. | 04 AR5. |
| Full rewrite versus substantial refactor | Keep/replace based on requirements and migration cost/proof. | 04 §8; M1. |
| Supported OS floor | Current macOS 13 preserved. | Separate recorded decision if newer-only features are desired. |
| Distribution/notarization | Verify separately from ad-hoc package builds. | 09 M8. |

## 6. What has not been promised as completed

No source defect is fixed by these documents. No new browser/Cursor adapter, chat, profile model, daily AI question, market service, reminder, Xcode target, storage migration, or release is implemented by this planning task. No private import or provider request was authorized or performed as part of writing it.

The agreed direction is complete enough to guide implementation. The open decisions are named so future work can resolve them without inventing user preferences or losing the core goal.
