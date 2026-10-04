# Integration review

Reviewed 2026-09-28 on Apple Silicon, macOS 26.5.2.

## Code Insights

[Code Insights](https://github.com/melagiri/code-insights) is MIT-licensed and
has session providers for Claude Code, Cursor, Codex CLI, Copilot CLI, and VS
Code Copilot Chat. It parses those sources into local SQLite and offers a Node
CLI, Hono API, and React dashboard. Its current feature set also includes
AI-generated scores and cross-session analysis.

Reflect does not embed its runtime or copy its parsers. Reflect is a native
SwiftUI app with a smaller local event model, separates observed facts from user
corrections, and treats Cursor/VS Code stores as unverified until their formats
are independently checked. This keeps the first release free of a second app
stack and avoids adopting a score-based assessment that Reflect cannot support
from the evidence it currently imports.

## ActivityWatch

[ActivityWatch](https://github.com/ActivityWatch/activitywatch) is MPL-2.0.
Its local server exposes bucket and timestamped-event APIs; optional browser
watchers can add website activity. The [official downloads page](https://activitywatch.net/downloads/)
currently lists the stable macOS downloads for Intel, while its v0.14.0b8
pre-release lists Apple Silicon downloads and warns that it may be unstable.
This Mac is Apple Silicon, and ActivityWatch is not installed, so Reflect does
not add it as a required dependency or install it automatically. A future
optional connector can read selected buckets from a local server after the user
chooses to enable it.

## Source boundaries in this release

- Real local import completed: one recent Codex CLI session file. The adapter
  saved 2,009 parsed events into Reflect's local Application Support store,
  and today's editable factual draft has two coaching prompts awaiting answers.
- Fixture-tested adapters: Claude Code JSONL and Copilot CLI JSONL. The Copilot
  CLI adapter does not establish compatibility with VS Code Copilot Chat.
- Detected but not read: Cursor and VS Code workspace SQLite stores.
- Not present: ActivityWatch. No browser-history adapter is implemented.
- Git history requires the user to select a repository and reports commit
  metadata without claiming who authored a change.

## M2 Codex session/turn import

The richer Codex path is implemented as an explicit, read-only import into
Reflect's additive `sessions.json` store. It retains normalized ordered turns
and linked content revisions separately from the legacy compact event stream;
display previews remain shorter than retained local text. Source IDs are kept
in typed source-ID fields, user-role turns remain attribution-unclear, and
malformed/skipped records are reflected in coverage. Session/turn import and
store migration are covered by synthetic temporary fixtures only. The parser
has not been checked against a fresh real rollout in this M2 work, so no
compatibility claim is made for unverified Codex record variants. Synthetic
tests cover local retrieval from Reflect-owned stores and provider-bound
serialization structure/privacy, but no provider was invoked and no
user-facing import/retrieval UI or runtime interaction was verified. The
context byte cap counts included provider-bound items; serialized framing
metadata adds overhead outside that content-byte total. Locators are screened
across all paths present in the loaded session/event stores; paths never
recorded there are not discoverable by this exact-locator check.
