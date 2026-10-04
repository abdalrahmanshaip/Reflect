import SwiftUI

public struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Image(systemName: "circle.dashed.inset.filled")
                .font(.system(size: 34))
                .foregroundStyle(ReflectPalette.accent)

            Text("About Reflect")
                .font(.title2.weight(.semibold))

            Text("Reflect 0.1.0 — a private engineering growth mirror.")
                .font(.headline)

            Text("""
            • Codex CLI, Claude Code, and Copilot CLI JSONL adapters are implemented and tested with synthetic fixtures only.
            • Cursor and VS Code workspace stores are shown as detected but not verified; their SQLite format is not read yet.
            • Commit events describe repository metadata and never assert authorship.
            • Reports, questions, and growth readings stay qualitative; insufficient evidence is stated openly.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(28)
        .frame(minWidth: 420, minHeight: 280, alignment: .topLeading)
        .background(ReflectPalette.page)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("About Reflect")
    }
}
