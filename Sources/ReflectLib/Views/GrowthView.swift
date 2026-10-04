import SwiftUI

/// Design A "Patterns": qualitative observations over imported evidence.
/// Deliberately score-free; missing evidence is stated as unknown, never as
/// lack of work.
struct GrowthView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let summary = store.growthSummary()
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 8) {
                    ObservedMark()
                    Text("Patterns")
                        .font(.callout.weight(.semibold))
                    Text("in your imported records")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                if summary.insufficientEvidence {
                    InsufficientEvidenceBanner(reason: summary.reason ?? "Insufficient evidence.")
                    explanation
                } else {
                    observations(summary)
                    weeklyBars(summary)
                }
                principles
            }
            .padding(.horizontal, 48)
            .padding(.top, 30)
            .padding(.bottom, 44)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(ReflectPalette.page)
        .navigationTitle("Patterns")
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Why nothing is shown here yet")
                .font(.callout.weight(.semibold))
            Text("Reflect refuses to guess. A pattern view needs at least \(AppConstants.minimumEventsForGrowth) imported records spread across at least \(AppConstants.minimumDistinctDaysForGrowth) different days. Start an import in Sources, work a few days, and this page will gradually fill with clearly labeled observations — never with a percent score or a career rank.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func observations(_ summary: GrowthSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ObservedMark()
                Text("Observations")
                    .font(.callout.weight(.semibold))
                Text("qualitative, always labeled")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(summary.observations) { observation in
                HStack(alignment: .top, spacing: 8) {
                    EvidenceLabelBadge(label: observation.label)
                    Text(observation.text)
                        .font(.callout)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ReflectPalette.card)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(ReflectPalette.outline, lineWidth: 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func weeklyBars(_ summary: GrowthSummary) -> some View {
        let maxCount = max(1, summary.weekly.map(\.eventCount).max() ?? 1)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ObservedMark()
                Text("Imported records per week (observed counts)")
                    .font(.callout.weight(.semibold))
            }
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
                                .fill(ReflectPalette.accent.opacity(0.7))
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
            Text("How Reflect reads patterns")
                .font(.callout.weight(.semibold))
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
