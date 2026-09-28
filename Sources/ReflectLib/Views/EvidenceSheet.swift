import SwiftUI
import AppKit

/// Full metadata for one imported event, its Open Evidence actions, and the
/// user's attribution correction (stored independently of imported facts).
struct EvidenceSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let event: EvidenceEvent
    @State private var correction: Attribution?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Evidence", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 6) {
                metadataRow("Source", event.sourceName)
                metadataRow("Type", event.kind.label)
                metadataRow("Timestamp", Fmt.dateTime(event.timestamp) + (event.timestampApproximate ? " (approximate; from file modification time)" : ""))
                metadataRow("Evidence ID", event.id)
                metadataRow("Evidence path", evidencePathText)
                metadataRow("Observed attribution", "\(event.observedAttribution.label) — \(event.observedAttributionNote)")
                metadataRow("Imported at", Fmt.dateTime(event.importedAt))
                if !event.detail.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Preview (stored locally, capped)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(event.detail)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Your attribution correction (stored separately from imported facts)")
                    .font(.callout.weight(.medium))
                Picker("Attribution", selection: $correction) {
                    Text("No correction (keep observed)").tag(Attribution?.none)
                    ForEach(Attribution.allCases) { value in
                        Text(value.label).tag(Attribution?.some(value))
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: correction) { value in
                    store.setCorrection(value, for: event.id)
                }
                Text("Corrections survive re-imports and event deletion. They never overwrite the observed record.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Open Evidence (reveal in Finder)") { revealInFinder() }
                Button("Open with default app") { openFile() }
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear {
            let resolved = store.effectiveAttribution(for: event)
            correction = resolved.isCorrected ? resolved.value : nil
        }
    }

    private var evidencePathText: String {
        guard let line = event.evidenceLine else { return event.evidencePath }
        return "\(event.evidencePath):\(line)"
    }

    private func metadataRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .trailing)
            Text(value)
                .font(.callout.monospaced())
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: event.evidencePath)])
    }

    private func openFile() {
        NSWorkspace.shared.open(URL(fileURLWithPath: event.evidencePath))
    }
}
