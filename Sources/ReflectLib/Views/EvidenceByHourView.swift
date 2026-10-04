import SwiftUI

/// Design A "By hour" tab: one lane per source, one mark per record at the
/// record's actual local time. Gaps mean nothing was imported for that time —
/// never that no work happened. Approximate timestamps get hollow marks.
struct EvidenceByHourView: View {
    let lanes: [(source: SourceKind, marks: [EvidenceHourMark])]

    init(events: [EvidenceEvent]) {
        self.lanes = EvidenceTimeline.lanes(for: events)
    }

    init(lanes: [(source: SourceKind, marks: [EvidenceHourMark])]) {
        self.lanes = lanes
    }

    var body: some View {
        if lanes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("No records are imported for this day.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(lanes, id: \.source) { lane in
                        HStack(spacing: 10) {
                            Text(lane.source.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 96, alignment: .leading)
                            LaneTrack(marks: lane.marks)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(lane.source.displayName): \(lane.marks.count) records across the day")
                    }
                    HStack {
                        Text("12 AM").frame(width: 96 + 10, alignment: .leading)
                        Spacer()
                        Text("6 AM")
                        Spacer()
                        Text("12 PM")
                        Spacer()
                        Text("6 PM")
                        Spacer()
                        Text("12 AM")
                            .lineLimit(1)
                            .fixedSize()
                            .frame(width: 34, alignment: .trailing)
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 0)

                    VStack(alignment: .leading, spacing: 4) {
                        Label("Each mark is one record at the time it was written. A gap means nothing was imported for that time, not that no work happened.", systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            HourMarkShape(approximate: false)
                            Text("explicit timestamp")
                            HourMarkShape(approximate: true)
                            Text("approximate timestamp (from file modification time)")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.top, 6)
                }
                .padding(16)
            }
        }
    }
}

private struct LaneTrack: View {
    let marks: [EvidenceHourMark]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.12))
                ForEach([6, 12, 18], id: \.self) { hour in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 0.5)
                        .offset(x: width * (hour / 24))
                }
                ForEach(marks) { mark in
                    HourMarkShape(approximate: mark.isApproximate)
                        .position(x: width * (EvidenceTimeline.hourFraction(mark.time) / 24), y: geometry.size.height / 2)
                }
            }
        }
        .frame(height: 12)
    }
}

private struct HourMarkShape: View {
    let approximate: Bool

    var body: some View {
        if approximate {
            Circle()
                .strokeBorder(Color.secondary.opacity(0.8), lineWidth: 1)
                .frame(width: 5, height: 5)
                .background(ReflectPalette.card)
        } else {
            Circle()
                .fill(Color.secondary.opacity(0.85))
                .frame(width: 4, height: 4)
        }
    }
}
