# Reflect

A private, local-first engineering growth mirror for software engineers who work
with AI coding tools (Copilot, Cursor, Codex, Claude Code). Reflect imports your
own local session evidence on demand, turns it into an editable daily report with
deterministic coaching questions, and shows cautious weekly and growth readings —
clearly separating **observed facts**, **app-generated inference**, and **your
corrections and answers**. No scores, no ranks, no fabricated competence
assessments.

Native SwiftUI macOS app, built with Swift Package Manager only. No third-party
dependencies; system frameworks only. No network calls unless *you* configure an
AI provider *and* explicitly run an analysis.

## Launch

```bash
./script/build_and_run.sh            # build (release), create app archive, launch
./script/build_and_run.sh --verify   # build + tests + app archive checks, no launch
swift build                          # debug build only
swift run reflect-test-runner        # authoritative core test suite (59 tests)
swift test                           # Swift Testing delegation target
```

Requirements: macOS 13+, Apple Silicon or Intel Mac, Command Line Tools (the app
is developed and verified with CLT only; full Xcode is not required).

`./script/build_and_run.sh` stops any previously running instance, rebuilds and
ad-hoc signs the app under `/tmp`, creates `../Reflect-macOS.zip`, then opens
the app with `/usr/bin/open -n`. The archive contains the app bundle only.

### A note on `swift test` on this machine

The Command Line Tools on the development machine ship the Swift Testing
framework, but its SwiftPM integration silently reports success without executing
tests (the generated test bundle's entry point is never invoked by
`swiftpm-testing-helper`). Therefore the authoritative test command is:

```bash
swift run reflect-test-runner
```

It prints every test, a summary, and exits non-zero on failure.
`swift test` still builds and, on toolchains where Swift Testing executes
normally (e.g. full Xcode), it runs the same suite via a delegation test.

## Privacy

- **Local first.** All data stays in `~/Library/Application Support/Reflect` as
  readable JSON: `events.json`, `corrections.json`, `reports.json`,
  `settings.json`, `manifests.json`. API keys live only in the Keychain.
- **Imports are opt-in.** Availability scanning reads directory listings and file
  metadata only — never file contents. Contents are read exclusively when you
  press an Import button.
- **Read-only sources.** Source histories are never modified or deleted.
- **Exclusions.** Settings lets you define path tokens; anything matching is
  skipped before it is read.
- **No demo data.** The repository and app ship with zero session data. The
  fixtures used by tests are synthetic and live in temporary directories only.
- **No automatic network.** Import never touches the network. The only networking
  code path is the explicit "Run analysis" action after you enable and configure
  a provider. While AI is disabled (the default), no request can be made.

## Source status

| Source | Location | Status in this version |
| --- | --- | --- |
| Codex CLI | `~/.codex/sessions/**/rollout-*.jsonl` | Implemented; imports only after you opt in |
| Claude Code | `~/.claude/projects/**/*.jsonl` | Implemented (tolerant JSONL, synthetic-fixture verified) |
| Copilot CLI | `~/.copilot/session-state/*/events.jsonl` | Implemented (tolerant JSONL; only clear user/agent/tool markers are imported) |
| Cursor | `~/Library/Application Support/Cursor/User/workspaceStorage/*/state.vscdb` | **Detected; format not yet verified.** Not read, not imported. |
| VS Code | `~/Library/Application Support/Code/User/workspaceStorage/*/state.vscdb` | **Detected; format not yet verified.** Not read, not imported. |
| Git (local) | any repository you pick manually | Implemented (read-only `git log` metadata) |
| ActivityWatch | — | Not implemented |

The integration choice for Code Insights and ActivityWatch is documented in
[the integration review](docs/INTEGRATIONS.md). Imported session records stay
in this user's Application Support folder; they are not part of the app archive
or repository.

The Sources tab shows, per source: availability, detected file count, last
successful import, imported event count, and any gaps or notes. Availability
without an explicit import never reads file contents.

## Attribution and evidence

- Every imported event carries: source name, timestamp (explicit, or flagged as
  approximate when derived from file modification time), a stable evidence ID,
  and the source file path (+ line where applicable).
- **Open Evidence** on any event reveals the backing file in Finder or opens it
  with the default app.
- Imported events have an **observed** structural attribution (`Observed:
  Agent/Unclear`). Transcript roles that could contain tool-injected context are
  recorded as `Unclear`, never as "you".
- Your **corrections** (You / Agent / Unclear) are stored in a separate file,
  survive re-imports and deletions, and always win over the observed label.
- Commit events state plainly: *commit metadata only; authorship is not
  asserted*.

## AI provider behavior

- Off by default. Settings → "Enable AI analysis" plus endpoint, model, Keychain
  key, and per-million input/output prices.
- Endpoint is OpenAI-compatible (`/v1/chat/completions` is appended to base URLs
  automatically).
- Analysis is only triggered by an explicit button, and only the events you
  selected in the Today tab are serialized into the request.
- Cost math: rough local token estimate (chars/4) or provider-reported usage,
  per your choice; estimated cost is computed from the prices you entered.
- Until you run a first analysis, the UI reports the provider as *configured but
  not verified*. Nothing in Reflect claims a live integration that has not
  executed.

## Limitations (current version)

- Cursor and VS Code stores are detected but not parsed (SQLite; no third-party
  JSONL adapter possible). They are labeled as unverified rather than pretend.
- JSONL adapters are written tolerantly from public format knowledge and tested
  against synthetic fixtures; unknown record types are skipped, not guessed.
- Daily/weekly/growth readings are qualitative and count-based. There is
  deliberately no percent score and no career rank anywhere in the app.
- The provider client has not been exercised against a live endpoint in
  development (by design: no external calls during development).
- Keychain writes may prompt depending on your keychain settings; failures are
  surfaced in the UI instead of silently falling back to disk.

## Next best improvement

Verify the Cursor/VS Code `state.vscdb` format against a copy the user provides
and add a read-only SQLite adapter (via the system `sqlite3` CLI) with the same
fixture-test discipline — this would close the biggest coverage gap. After that:
window restore state and export/redaction tools for reports.

## Repository layout

```
Sources/ReflectLib        Models, Services (adapters, persistence, provider), Stores, Support, Views
Sources/ReflectAppMain    @main entry point
Tests/ReflectTestRunner   Explicit core test suite (authoritative on CLT machines)
Tests/ReflectSwiftTests   Swift Testing delegation target for `swift test`
script/build_and_run.sh   Build, package Reflect-macOS.zip, launch / --verify
```

Do not commit real personal session data anywhere in this repository.
