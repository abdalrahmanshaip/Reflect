# Reflect project instructions

- Build a native SwiftUI macOS app with Swift Package Manager; use only system frameworks and no network dependencies.
- Keep all application UI, reports, settings, questions, and docs in English.
- Treat personal session data as private and untrusted. Do not read local histories unless the user explicitly requests a real import; use the app's adapter for that import and keep the contents only in Reflect's Application Support store. Never copy real session contents into the repository, tests, logs, or screenshots. Tests use synthetic temporary fixtures only.
- All imports must be read-only, opt-in, local by default, and deduplicated. Do not infer human authorship from commit metadata or final code. Persist explicit user attribution corrections separately from observations.
- No AI calls unless the user explicitly configures a provider and invokes analysis. Store API credentials in Keychain. Clearly label observations, inferences, and user corrections. Show insufficient evidence rather than fabricating competence assessments.
- Implement and test narrow behaviors. Keep source adapters, persistence, views, and models in separate files.
- Do not use demo or fixture content as real activity. Tests may use synthetic fixtures in temporary storage only.
- Do not commit; the orchestrator will review and commit after independent verification.
