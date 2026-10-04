import SwiftUI
import AppKit

struct SourcesView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    ObservedMark()
                    Text("Sources")
                        .font(.callout.weight(.semibold))
                    Text("imports run only when you start them")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                HStack {
                    Button("Import all available sources") {
                        store.importAllAvailable()
                    }
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
            .padding(.horizontal, 48)
            .padding(.top, 30)
            .padding(.bottom, 44)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(ReflectPalette.page)
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
            .accessibilityElement(children: .contain)

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

            if let result = store.importResults[kind] {
                importResultRow(result)
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
        .background(ReflectPalette.card)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(ReflectPalette.outline, lineWidth: 0.5)
        }
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

    /// This source's own retained import outcome. Safe status only: source
    /// name, record counts, and honest state — never payload text.
    private func importResultRow(_ result: ImportSourceResult) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: resultIcon(result.status))
                .font(.caption2.bold())
            Text(result.message)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(resultColor(result.status))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func resultIcon(_ status: ImportSourceResult.Status) -> String {
        switch status {
        case .imported: return "checkmark.circle"
        case .importerNote: return "info.circle"
        case .retryableSaveFailure, .manifestSaveFailed: return "exclamationmark.triangle"
        }
    }

    private func resultColor(_ status: ImportSourceResult.Status) -> Color {
        switch status {
        case .imported: return .green
        case .importerNote: return .secondary
        case .retryableSaveFailure: return .red
        case .manifestSaveFailed: return .orange
        }
    }

    private func isImportAllowed(_ kind: SourceKind, availability: SourceAvailability?) -> Bool {
        ImportRules.isImportAllowed(
            kind: kind,
            importing: store.importing,
            enabledSources: store.settings.enabledSources,
            gitRepositoryPath: store.settings.gitRepositoryPath,
            formatVerified: kind.formatVerified
        )
    }

    private func enabledBinding(_ kind: SourceKind) -> Binding<Bool> {
        Binding(
            get: { store.settings.enabledSources.contains(kind) },
            set: { enabled in
                // Staged through the store: a failed preference write stays
                // unpublished and the toggle re-reads the durable value.
                store.updateSettings { settings in
                    if enabled {
                        settings.enabledSources.insert(kind)
                    } else {
                        settings.enabledSources.remove(kind)
                    }
                }
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
        store.updateSettings { $0.gitRepositoryPath = url.path }
        store.refreshAvailability()
    }
}
