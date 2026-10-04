# AI conversation and growth assessment implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` for authorized native execution, or `superpowers:subagent-driven-development` when subagent execution is explicitly authorized. Execute task by task using checkbox tracking. Read plans 04–05 and use a fake agent for automated checks. Real analysis requires explicit configuration and invocation. Do not commit automatically.

**Goal:** Answer natural questions about engineering growth with useful, correctable, historically comparable reasoning.\
**Architecture:** A conversation store coordinates explicit requests, bounded context, restricted agent execution, response validation, and durable message/assessment memory. Profile and competence claims remain dated interpretations backed by references and coverage.\
**Tech stack:** Swift, SwiftUI, Foundation Process/structured concurrency, Codable, existing supported CLI adapters and Keychain boundary.\
**Spec:** [01](01-product-vision-and-requirements.md), requirements R01–R04 and R08–R13.

## Global constraints

All spec section 9 constraints apply. No launch/background/provider call occurs merely because evidence exists. Local storage and a local CLI do not imply local model inference; configured CLIs may use remote services. Credentials remain in their supported auth mechanism or Keychain, never transcripts/settings JSON/logs.

## Review focus

1. Fluent output must not assert competence, authorship, seniority, or market rank without sufficient support.
2. No prior AI opinion may become proof of itself in later profile updates.
3. Delayed/canceled/retried responses must not overwrite newer messages or update another conversation.
4. Provider errors, invalid output, and unknown usage must produce honest state without fabricated cost figures.
5. Corrections and missing source coverage must affect answers rather than being ignored behind polished wording.

## 1. Conversational behavior

Allow ordinary questions and follow-ups. Infer intent for routing, but do not require the user to choose from a static role/rubric menu. Useful intents include progress comparison, current work profile, weaknesses, understanding, reliance on agents, next steps, daily reflection, and market comparison.

A good response usually contains a direct answer, a brief explanation, the important uncertainty, and an actionable next step. Scale depth to the question. Do not force all answers into long reports or expose every underlying record.

The assistant should be willing to challenge a weak inference or disagree with the user's conclusion. Avoid automatic praise, confidence theater, and arbitrary grades. If evidence is insufficient, name the missing signal and explain how to obtain it.

If the user asks something outside the approved history, state the available basis. General advice is possible when clearly distinguished from a personalized conclusion. Current market facts require the separate research capability in plan 08.

## 2. Agent integration

Current analysis support exposes Codex CLI and Claude Code. Copilot CLI exists as a model case but is excluded from supported analysis agents pending a verified adapter. Importing a source does not make its executable safe or compatible for analysis.

Reuse the restricted invocation boundary where valid: explicit selection/configuration, supported executable discovery, sanitized environment, private temporary working directory, bounded stdin, timeout, output limits, and no source-store path access. Verify installed CLI behavior at implementation time; flags and authentication output can change.

The existing process timeout is 120 seconds and output limit is 64 KiB. Retain these initial safety bounds unless a measured requirement leads to a recorded change. The UI needs cancel/timeout/error states; real streaming is optional until a provider format supports it. Do not simulate streaming to disguise a blocking call.

Provider capability must be enforced by the transport/invocation, not only by asking the model to avoid tools. Imported text is untrusted data and cannot override the request's scope or grant tools/network/filesystem authority. A tool-capable future agent can receive only explicitly designed Reflect-owned read tools; broad workstation access is outside this plan.

Submitting a chat message with a configured enabled agent is an explicit invocation. It may select relevant already-approved stored context within the active scope; it does not authorize reading new local histories. Keep the scope understandable without requiring manual record selection every turn.

## 3. Inferred profile

Maintain possible work-role fits instead of assigning a permanent identity. Technology frequency is one observation, not the whole profile. Consider task types, decision ownership, debugging/validation behavior, system boundaries, and context breadth where supported.

Profile output must distinguish:

- Current observed work pattern.
- Tentative role fit inferred from that pattern.
- Demonstrated dimensions and their limits.
- Explicit user-stated aspirations.
- Areas with insufficient evidence.

An inferred full-stack pattern does not prohibit a systems-engineering aspiration or prove a formal title. Multiple plausible role fits may coexist. A conversational correction creates a dated correction and a revised interpretation; it does not rewrite old observations.

Do not classify seniority solely from prompt style, vocabulary, commit volume, agent model choice, final code complexity, or the agent's quality.

## 4. Comparable assessment dimensions

Proposed first rubric, to be confirmed during contract review:

| Dimension | Signals to look for | Signals that are insufficient alone |
| --- | --- | --- |
| Problem framing | Clarifying requirements, constraints, acceptance, and scope. | A long prompt or many tasks. |
| Debugging | Reproduction, competing hypotheses, discriminating checks, causal reasoning. | Repeatedly asking an agent to fix an error. |
| Design judgment | Alternatives, tradeoffs, failure modes, justified decisions. | Complex generated architecture. |
| Validation | Relevant tests/checks, interpreting results, understanding proof limits. | An agent claiming tests passed. |
| Ownership and independence | Explicit decisions, review, corrections, accepted risks, ability to explain. | Commit authorship, approval clicks, or task completion alone. |
| Learning transfer | Applying an earlier concept to a new context and explaining why. | Repeated exposure to the same technology. |

Assess dimensions qualitatively, with dated references, confidence reasons, and unknown areas. No numeric competence score, universal engineer rank, or percentile is part of the agreed product.

The daily answer can clarify a dimension, but it is labeled self-report. A later independently observable application can strengthen the interpretation. Reflect should avoid inferring regressions when a source stops collecting or a quieter period yields less data.

## 5. Longitudinal comparison

Each snapshot records the assessed interval, supporting references, coverage, corrections, rubric/prompt/model versions, and the previous comparable snapshot where available.

Compare equivalent dimensions and suitable contexts. More difficult work may create more failures without indicating weaker ability. A switch in source, model, rubric, or data completeness can change an assessment; label the comparison limitation rather than claiming an improvement.

When no suitable baseline exists, establish a tentative baseline and explain what future evidence would help. Preserve old snapshots with supersession metadata when new corrections invalidate a claim.

Generated profile and assessment proposals must pass validation before becoming stored memory. A narrative reply can be retained as a generated message without promoting every sentence to a durable profile fact.

## 6. Response validation and uncertainty

Require structured claims with supporting IDs drawn from the actual `ContextEnvelope`. Reject unknown references, impossible dates, unsupported authorship, unsourced market claims, and attempts to alter permissions.

Provider text may fail structured parsing. In that case, retain a clearly labeled generated response if safe to display, but do not persist malformed claims as assessment/profile updates. Show a useful failure/retry state if the output cannot be used. A schema failure must never be silently repaired by inventing evidence IDs.

Use qualitative confidence with a reason, not invented statistical probabilities. Distinguish disagreement, uncertainty, missing coverage, and evidence of a weakness; they are different conclusions.

## 7. Operation and persistence states

Track `draft`, `queued`, `running`, `completed`, `failed`, and `canceled` messages/runs. Record request IDs, start/finish time, selected agent/model, context scope/revision, and whether transmission may have occurred.

Persist submitted user text before beginning a response when possible. A failed local save must not produce a fake saved conversation. Preserve a generated result as an unsaved draft if its write fails and offer retry without re-invoking the agent.

A canceled run may already have sent context. Unknown token usage/cost stays unknown; do not display zero. The current CLI result returns no token usage/cost. Do not calculate subscription usage from message counts. Explain provider billing/limits only from supported current information.

## 8. Files and interfaces

Create the conversation/profile/assessment/claim models from plan 04; `Stores/ConversationStore.swift`, `Stores/IntelligenceStore.swift`; and `Services/Intelligence/ConversationService.swift`, `ResponseValidator.swift`, `ProfileInterpreter.swift`, `AssessmentComparator.swift`.

Adapt `Services/Provider/AnalysisService.swift` and `Services/Analysis/AnalysisProcessRunner.swift` beneath `ConversationResponding.respond(to:context:)`. Keep authentication discovery separate from inference. Modify `Views/OptionalAnalysisView.swift` and new conversation views to observe the actual store state.

Tests: `ConversationServiceTests.swift`, `ResponseValidationTests.swift`, `ProfileInferenceTests.swift`, `AssessmentComparisonTests.swift`, and `ConversationPersistenceTests.swift`, registered in `RunnerMain.swift`.

## 9. Tasks

### Task C1: A durable fake-agent conversation slice

- [ ] Test first message, follow-up, relaunch, failed local save, retry, cancel, and out-of-order response with a fake runner.
- [ ] Implement request IDs, context integration, and persist-before-publish message states.
- [ ] Verify request scope contains only approved stored material and follows conversational context without rereading originals.
- [ ] Connect the native composer from plan 03 and verify unsent/failed drafts survive navigation.
- [ ] Run `swift run reflect-test-runner` and the synthetic UI fixture.

### Task C2: Validated profile and corrections

- [ ] Test frontend-heavy evidence with an explicitly different aspiration; the profile must keep them separate.
- [ ] Test agent-authored work and injected user-role content; no unsupported human attribution may result.
- [ ] Test unknown reference IDs, malformed structured output, and a prior AI opinion repeated as supposed new proof.
- [ ] Implement validation and versioned profile proposals; save only accepted validated interpretations.
- [ ] Verify a conversational correction is visible in later answers while original observations remain unchanged.

### Task C3: Comparable progress reasoning

- [ ] Add synthetic earlier/recent examples for all six dimensions and an absent-baseline example.
- [ ] Assert weak/unknown dimensions do not receive a fabricated numeric score.
- [ ] Test collection gaps, harder tasks, rubric/model changes, and corrected evidence; comparisons must disclose limits.
- [ ] Implement `AssessmentComparator` against versioned snapshots and supporting references.
- [ ] Run quality evaluation scenarios as well as deterministic contract tests; record what the fake agent proves versus what real model evaluation would still require.

### Task C4: Supported agent transport and runtime proof

- [ ] Test missing executable, expired auth, changed auth output, timeout, empty output, large output, and cancellation with fake subprocess results.
- [ ] Verify restriction mechanisms against the installed documented CLI version before exposing it.
- [ ] Update provider/status/privacy copy to match actual selected-agent behavior and unknown usage.
- [ ] A real configured analysis may be tested only after an explicit invocation; use synthetic content for shared artifacts and record provider-specific limitations.

## 10. Completion gate

The user can ask and follow up naturally, restore the conversation, correct an inferred profile, receive a supported progress comparison, and see a useful next step. Claims distinguish evidence and interpretation, no static role/market is required, and unsupported provider or model behavior is stated rather than hidden.

## 11. Research references

[SFIA's explanation of its framework](https://sfia-online.org/en/about-sfia/how-sfia-works) separates skill content from responsibility/autonomy and related professional characteristics; it is a useful reference for avoiding title-only assessment. The proposed Reflect rubric is not an official SFIA certification or hiring verdict.

[Anthropic context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) supports focused context and durable memory. It does not establish that a language model can reliably infer competence from arbitrary activity; that remains a product evaluation responsibility.
