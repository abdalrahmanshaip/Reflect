import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    @State private var newExclusion = ""
    @State private var apiKeyDraft = ""
    @State private var apiKeyMessage: String?

    var body: some View {
        Form {
            privacySection
            aiSection
            dataSection
            aboutSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onChange(of: store.settings) { _ in
            store.persistSettings()
        }
    }

    // MARK: Privacy

    private var privacySection: some View {
        Section("Privacy & exclusions") {
            Text("Any path containing one of these tokens is skipped during imports. Matching is case-insensitive. Exclusions apply before anything is read.")
                .font(.callout)
                .foregroundStyle(.secondary)

            ForEach(store.settings.exclusions, id: \.self) { token in
                HStack {
                    Text(token)
                        .font(.callout.monospaced())
                    Spacer()
                    Button(role: .destructive) {
                        store.settings.exclusions.removeAll { $0 == token }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }

            HStack {
                TextField("Add exclusion token (e.g. PrivateProject)", text: $newExclusion)
                    .onSubmit(addExclusion)
                Button("Add") { addExclusion() }
                    .disabled(newExclusion.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Text("All processing is local. Nothing leaves this Mac during import. Personal session data is never copied into the app bundle or repository.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func addExclusion() {
        let token = newExclusion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        if !store.settings.exclusions.contains(token) {
            store.settings.exclusions.append(token)
        }
        newExclusion = ""
    }

    // MARK: AI provider

    private var aiSection: some View {
        Section("AI analysis (optional, off by default)") {
            Toggle("Enable AI analysis", isOn: $store.settings.aiEnabled)
            Text("While disabled, Reflect never contacts the network — importing included. When enabled, analysis still runs only when you explicitly press Run, and only the evidence you selected is sent.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("Endpoint (OpenAI-compatible base URL)", text: $store.settings.providerEndpoint)
                .textFieldStyle(.roundedBorder)
            TextField("Model", text: $store.settings.providerModel)
                .textFieldStyle(.roundedBorder)

            HStack {
                TextField("Input price per 1M tokens (USD)", value: $store.settings.pricePerMillionInput, format: .number)
                    .textFieldStyle(.roundedBorder)
                TextField("Output price per 1M tokens (USD)", value: $store.settings.pricePerMillionOutput, format: .number)
                    .textFieldStyle(.roundedBorder)
            }

            Picker("Token usage for cost math", selection: $store.settings.usageMode) {
                ForEach(UsageMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            HStack {
                SecureField("API key (stored in Keychain only)", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                Button("Save key") {
                    store.setAPIKey(apiKeyDraft)
                    apiKeyDraft = ""
                    apiKeyMessage = store.hasAPIKey() ? "Key stored in Keychain." : "Key storage failed."
                }
                .disabled(apiKeyDraft.isEmpty)
                Button(role: .destructive) {
                    store.deleteAPIKey()
                    apiKeyMessage = "Key deleted."
                } label: {
                    Text("Delete key")
                }
                Text(store.hasAPIKey() ? "Key present" : "No key stored")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let message = apiKeyMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Provider status") {
                Text(statusText)
                    .font(.callout)
            }
        }
    }

    private var statusText: String {
        switch store.aiStatus() {
        case .disabled:
            return "Disabled (default). No network calls are made."
        case .incomplete(let reason):
            return "Incomplete: \(reason)"
        case .ready:
            return "Configured and able to run. Accuracy against a live endpoint is unverified until you run an analysis."
        }
    }

    // MARK: Data

    private var dataSection: some View {
        Section("Local data") {
            LabeledContent("Data folder") {
                Text(store.dataDirectory.path)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
            HStack {
                Button("Reveal data folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.dataDirectory])
                }
                Button("Re-count sources") {
                    store.refreshAvailability()
                }
            }
            Text("Everything persists as readable JSON: events, corrections, reports, settings, and import state. API keys live only in Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section("About & limitations") {
            Text("""
            Reflect 0.1.0 — a private engineering growth mirror.
            - Codex CLI, Claude Code, and Copilot CLI JSONL adapters are implemented and tested with synthetic fixtures only.
            - Cursor and VS Code workspace stores are shown as detected but not verified; their SQLite format is not read yet.
            - Commit events describe repository metadata and never assert authorship.
            - Reports, questions, and growth readings stay qualitative; insufficient evidence is stated openly.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}
