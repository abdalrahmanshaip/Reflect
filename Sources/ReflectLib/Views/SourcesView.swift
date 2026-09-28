import SwiftUI
import AppKit

struct SourcesView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button("Import all available sources") {
                        store.importAllAvailable()
                    }
                    .disabled(store.importing.isEmpty == false && store.importing.count == SourceKind.allCases.count)
                    Spacer()
                    Button("Refresh availability") {
                        store.refreshAvailability()
                    }
                }

                Text("Imports never run automatically. Each import is read-only, local, and deduplicated by stable evidence ids.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let summary = store.lastImportSummary {
                    Text(summary)
                        .font(.callout)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.blue.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                ForEach(SourceKind.allCases) { kind in
                    sourceCard(kind)
                }
            }
            .padding(20)
        }
        .navigationTitle("Sources")
    }

    @ViewBuilder
    private func sourceCard(_ kind: SourceKind) -> some View {
        let availability = store.availability[kind]
        let manifest = store.manifests[kind]

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(kind.displayName)
                    .font(.headline)
                availabilityBadge(availability)
                Spacer()
                if store.importing.contains(kind) {
                    ProgressView()
                        .scaleEffect(0.6)
                }
                Button("Import") {
                    store.importSource(kind)
                }
                .disabled(!isImportAllowed(kind, availability: availability))
            }

            HStack(spacing: 18) {
                Label(availability?.displayText ?? "Not scanned", systemImage: "folder")
                    .font(.callout)
                Label("Last import: \(Fmt.relative(manifest?.lastImport))", systemImage: "clock")
                    .font(.callout)
                Label("Imported: \(manifest?.importedEventCount ?? 0)", systemImage: "tray.2")
                    .font(.callout)
                if let files = manifest?.filesScanned, files > 0 {
                    Label("Files scanned: \(files)", systemImage: "doc.on.doc")
                        .font(.callout)
                }
            }

            if let note = availability?.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let note = manifest?.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if kind == .gitLocal {
                gitControls
            } else {
                Toggle("Include this source in imports", isOn: enabledBinding(kind))
                    .toggleStyle(.checkbox)
            }

            Divider()
        }
        .padding(12)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func availabilityBadge(_ availability: SourceAvailability?) -> some View {
        let status = availability?.status ?? .missing
        let color: Color
        let text: String
        switch status {
        case .detected:
            color = .green
            text = "Available"
        case .detectedUnverified:
            color = .orange
            text = "Detected; format not yet verified"
        case .missing:
            color = .secondary
            text = "Not detected"
        case .manual:
            color = .blue
            text = "Selected"
        }
        return Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func isImportAllowed(_ kind: SourceKind, availability: SourceAvailability?) -> Bool {
        guard !store.importing.contains(kind) else { return false }
        guard store.settings.enabledSources.contains(kind) else { return false }
        if kind == .gitLocal {
            return !(store.settings.gitRepositoryPath ?? "").isEmpty
        }
        return kind.formatVerified
    }

    private func enabledBinding(_ kind: SourceKind) -> Binding<Bool> {
        Binding(
            get: { store.settings.enabledSources.contains(kind) },
            set: { enabled in
                if enabled {
                    store.settings.enabledSources.insert(kind)
                } else {
                    store.settings.enabledSources.remove(kind)
                }
                store.persistSettings()
            }
        )
    }

    private var gitControls: some View {
        HStack {
            Text(store.settings.gitRepositoryPath ?? "No repository selected")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Button("Choose repository…") { chooseRepository() }
            Text("Commit identity is metadata; authorship is never asserted.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func chooseRepository() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a local git repository. Reflect reads commit metadata read-only."
        panel.directoryURL = store.settings.gitRepositoryPath.map { URL(fileURLWithPath: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.settings.gitRepositoryPath = url.path
        store.persistSettings()
        store.refreshAvailability()
    }
}
