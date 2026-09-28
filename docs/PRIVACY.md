# Reflect privacy model

## What stays on this Mac

- Imported evidence, corrections, reports, settings, and import bookkeeping live
  in `~/Library/Application Support/Reflect` as JSON files.
- The AI API key, if the user stores one, lives in the login Keychain under the
  service `Reflect.provider` (generic password). It is never written to disk
  files, logs, or the repository.

## What leaves this Mac

- Nothing, unless the user enables AI analysis in Settings, stores an API key,
  selects specific evidence records in the Today tab, and presses
  "Run analysis on selected evidence". That request contains only the selected
  records' metadata (id, source, timestamp, type, observed attribution) and a
  short capped preview the user already saw locally.

## What Reflect never does

- It never reads source histories at launch or while browsing availability —
  availability is computed from directory listings and file metadata only.
- It never writes to, moves, or deletes anything in source directories.
- It never copies session contents into the app bundle, repository, tests,
  logs, or screenshots. Test fixtures are synthetic and live in temp dirs.
- It never asserts human authorship from commit metadata or transcript roles;
  attribution labels are structural observations the user can correct.
- It never fabricates competence scores; insufficient evidence is stated
  explicitly instead.
