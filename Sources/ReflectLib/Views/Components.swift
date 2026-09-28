import SwiftUI

struct AttributionBadge: View {
    let value: Attribution
    let isCorrected: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: isCorrected ? "person.crop.circle.badge.checkmark" : "scope")
                .font(.caption2)
            Text(isCorrected ? "Your correction: \(value.label)" : "Observed: \(value.label)")
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(isCorrected ? Color.purple.opacity(0.16) : Color.blue.opacity(0.12))
        .foregroundStyle(isCorrected ? .purple : .blue)
        .clipShape(Capsule())
        .help(isCorrected
              ? "You corrected the attribution for this event. Stored independently of imported facts."
              : "Structural attribution recorded at import time. Not asserted as human authorship.")
    }
}

struct EvidenceLabelBadge: View {
    let label: EvidenceLabel

    var body: some View {
        Text(label.displayName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.16))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch label {
        case .observed: return .blue
        case .inference: return .orange
        case .correction: return .purple
        }
    }
}

struct SourceCountBadge: View {
    let kind: SourceKind
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Text(kind.displayName)
                .font(.caption)
            Text("\(count)")
                .font(.caption.monospacedDigit().bold())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.12))
        .clipShape(Capsule())
    }
}

struct InsufficientEvidenceBanner: View {
    let reason: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
            VStack(alignment: .leading, spacing: 2) {
                Text("Insufficient evidence")
                    .font(.headline)
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .foregroundStyle(.orange)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
