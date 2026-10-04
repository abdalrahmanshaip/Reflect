import SwiftUI

/// Design A "What happened" block: one observed serif sentence, the compact
/// factual lines beneath it, and honest status notes when evidence is missing
/// or too sparse for a question. Pure display over a `DayOverview`.
struct TodayOverviewView: View {
    let overview: DayOverview

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ObservedMark()
                Text("What happened")
                    .font(.callout.weight(.semibold))
                Text("from your imported records")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            if let sentence = overview.observedSentence {
                Text(sentence)
                    .font(.system(size: 24, weight: .regular, design: .serif))
                    .lineSpacing(4)
                    .accessibilityLabel("What happened: \(sentence)")
            }

            if !overview.facts.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(overview.facts) { fact in
                        HStack(alignment: .top, spacing: 8) {
                            switch fact.marker {
                            case .observed:
                                ObservedMark()
                                    .padding(.top, 7)
                            case .correction:
                                YourMark()
                                    .padding(.top, 6)
                            }
                            Text(fact.text)
                                .font(.callout)
                                .foregroundStyle(fact.marker == .correction ? ReflectPalette.yours : .secondary)
                                .accessibilityLabel(fact.marker == .correction ? "Your correction: \(fact.text)" : fact.text)
                        }
                    }
                }
                .padding(.top, 6)
            }

            if let note = overview.statusNote {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }
}
