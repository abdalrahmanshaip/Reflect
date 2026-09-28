import SwiftUI

struct GrowthView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let summary = store.growthSummary()
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if summary.insufficientEvidence {
                    InsufficientEvidenceBanner(reason: summary.reason ?? "Insufficient evidence.")
                    explanation
                } else {
                    observations(summary)
                    weeklyBars(summary)
                }
                principles
            }
            .padding(20)
        }
        .navigationTitle("Growth")
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Why nothing is shown here yet")
                .font(.headline)
            Text("Reflect refuses to guess. A growth reading needs at least \(AppConstants.minimumEventsForGrowth) imported events spread across at least \(AppConstants.minimumDistinctDaysForGrowth) different days. Start an import in Sources, work a few days, and this page will gradually fill with clearly labeled observations — never with a percent score or a career rank.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func observations(_ summary: GrowthSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Observations", systemImage: "eye")
                .font(.headline)
            ForEach(summary.observations) { observation in
                HStack(alignment: .top, spacing: 8) {
                    EvidenceLabelBadge(label: observation.label)
                    Text(observation.text)
                        .font(.callout)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func weeklyBars(_ summary: GrowthSummary) -> some View {
        let maxCount = max(1, summary.weekly.map(\.eventCount).max() ?? 1)
        return VStack(alignment: .leading, spacing: 8) {
            Label("Imported events per week (observed counts)", systemImage: "chart.bar")
                .font(.headline)
            ForEach(summary.weekly) { week in
                HStack(spacing: 10) {
                    Text(week.id)
                        .font(.caption.monospacedDigit())
                        .frame(width: 90, alignment: .leading)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.15))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.accentColor.opacity(0.7))
                                .frame(width: geometry.size.width * CGFloat(week.eventCount) / CGFloat(maxCount))
                        }
                    }
                    .frame(height: 14)
                    Text("\(week.eventCount)")
                        .font(.caption.monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                }
            }
            Text("Counts reflect what has been imported, not total activity. Weeks before your first import show zero because no evidence exists — not because nothing happened.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var principles: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("How Reflect reads your growth", systemImage: "scale.3d")
                .font(.headline)
            Text("""
            - Observed facts come only from imported evidence and are labeled as such.
            - App-generated inferences are qualitative and always labeled; they describe imports, not you.
            - Your corrections and answers are stored separately and always win over observed labels.
            - Commit metadata never implies authorship. Where evidence is insufficient, Reflect says so.
            - There is deliberately no percent score and no definitive career rank.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}
