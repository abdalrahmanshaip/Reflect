import AppKit
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

/// Small value-state boundary used by custom clickable surfaces. Keeping the
/// enabled check here prevents a disabled control from retaining a hover tint
/// when its state changes while the pointer is over it.
struct ReflectHoverState: Equatable {
    private(set) var isHovered = false

    mutating func update(isHovered: Bool, isEnabled: Bool) {
        self.isHovered = isEnabled && isHovered
    }
}

/// Adds a restrained hover surface and a pointing-hand cursor to custom
/// clickable rows/cards. The cursor is provided by an AppKit cursor rectangle,
/// not NSCursor.push/pop, so view removal and nested tracking areas cannot leak
/// cursor state. Native controls keep their own platform affordances.
private struct ReflectClickableHoverModifier<S: Shape>: ViewModifier {
    let shape: S

    @Environment(\.isEnabled) private var isEnabled
    @State private var hoverState = ReflectHoverState()

    func body(content: Content) -> some View {
        content
            .overlay {
                if hoverState.isHovered && isEnabled {
                    shape
                        .fill(Color.primary.opacity(0.05))
                        .overlay(
                            shape.stroke(Color.primary.opacity(0.13), lineWidth: 0.75)
                        )
                }
            }
            .onHover { isHovered in
                hoverState.update(isHovered: isHovered, isEnabled: isEnabled)
            }
            .onChange(of: isEnabled) { enabled in
                if !enabled {
                    hoverState.update(isHovered: false, isEnabled: false)
                }
            }
            .overlay {
                if isEnabled {
                    ReflectPointingHandCursor()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
    }
}

extension View {
    func reflectClickableHover<S: Shape>(_ shape: S) -> some View {
        modifier(ReflectClickableHoverModifier(shape: shape))
    }
}

private struct ReflectPointingHandCursor: NSViewRepresentable {
    func makeNSView(context: Context) -> CursorRectView {
        CursorRectView()
    }

    func updateNSView(_ nsView: CursorRectView, context: Context) {}

    final class CursorRectView: NSView {
        override func updateTrackingAreas() {
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(
                NSTrackingArea(
                    rect: bounds,
                    options: [.activeInKeyWindow, .cursorUpdate, .inVisibleRect],
                    owner: self,
                    userInfo: nil
                )
            )
            super.updateTrackingAreas()
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .pointingHand)
        }

        override func cursorUpdate(with event: NSEvent) {
            NSCursor.pointingHand.set()
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

// MARK: Design A visual language

/// Design A colors follow the window's Aqua/Dark Aqua appearance. Surface values
/// match the selected Today Window reference; semantic text stays system-adaptive.
enum ReflectPalette {
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }))
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func surface(light: UInt32, dark: UInt32) -> Color {
        dynamic(light: rgb(light), dark: rgb(dark))
    }

    static let window = surface(light: 0xF6F5F2, dark: 0x1F1E1C)
    static let sidebar = surface(light: 0xECEAE5, dark: 0x2A2927)
    static let page = surface(light: 0xFDFCFA, dark: 0x252422)
    static let card = surface(light: 0xFFFFFF, dark: 0x2D2C29)
    static let button = surface(light: 0xFFFFFF, dark: 0x3B3A37)
    static let outline = dynamic(
        light: NSColor(srgbRed: 28 / 255, green: 27 / 255, blue: 25 / 255, alpha: 0.17),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.15)
    )

    static let accent = dynamic(light: NSColor(srgbRed: 0x0A/255, green: 0x63/255, blue: 0xD8/255, alpha: 1),
                                dark: NSColor(srgbRed: 0x2F/255, green: 0x7F/255, blue: 0xEA/255, alpha: 1))
    static let inference = dynamic(light: NSColor(srgbRed: 0x8F/255, green: 0x5A/255, blue: 0x12/255, alpha: 1),
                                   dark: NSColor(srgbRed: 0xE2/255, green: 0xAC/255, blue: 0x62/255, alpha: 1))
    static let yours = dynamic(light: NSColor(srgbRed: 0x1D/255, green: 0x6F/255, blue: 0x6A/255, alpha: 1),
                               dark: NSColor(srgbRed: 0x72/255, green: 0xC8/255, blue: 0xBF/255, alpha: 1))
    static let serif = Font.system(.title2, design: .serif)
}

/// Graphite square — "Observed" in the Design A legend.
struct ObservedMark: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.secondary)
            .frame(width: 7, height: 7)
    }
}

/// Ochre diamond — "Suggested by Reflect" in the legend.
struct SuggestedMark: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .strokeBorder(ReflectPalette.inference, lineWidth: 1.25)
            .frame(width: 6.5, height: 6.5)
            .rotationEffect(.degrees(45))
    }
}

/// Teal dot — "Yours" in the legend (also the sidebar reflected dot).
struct YourMark: View {
    var body: some View {
        Circle()
            .fill(ReflectPalette.yours)
            .frame(width: 7, height: 7)
    }
}

/// The Design A prominent action (Save Reflection): solid accent fill, white
/// label, visibly dimmed when disabled. Custom style because prominent system
/// button styles don't reliably take a custom tint on every macOS version.
struct ProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(ReflectPalette.accent.opacity(isEnabled ? 1 : 0.3))
            )
            .foregroundStyle(isEnabled ? Color.white : Color.primary.opacity(0.55))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .reflectClickableHover(RoundedRectangle(cornerRadius: 7))
    }
}
