import Foundation
import AppKit
import SwiftUI
@testable import ReflectLib

struct DesignPaletteTests {
    static let suiteName = "DesignPaletteTests"

    func surfacesResolveToDesignATokensInBothAppearances() throws {
        let surfaces: [(String, Color, UInt32, UInt32)] = [
            ("window", ReflectPalette.window, 0xF6F5F2, 0x1F1E1C),
            ("sidebar", ReflectPalette.sidebar, 0xECEAE5, 0x2A2927),
            ("page", ReflectPalette.page, 0xFDFCFA, 0x252422),
            ("card", ReflectPalette.card, 0xFFFFFF, 0x2D2C29),
            ("button", ReflectPalette.button, 0xFFFFFF, 0x3B3A37)
        ]

        for (name, color, lightHex, darkHex) in surfaces {
            try expectEqual(resolvedHex(color, appearance: .aqua), lightHex, "\(name) light surface")
            try expectEqual(resolvedHex(color, appearance: .darkAqua), darkHex, "\(name) dark surface")
        }
    }

    private func resolvedHex(_ color: Color, appearance name: NSAppearance.Name) -> UInt32 {
        guard let appearance = NSAppearance(named: name) else { return 0 }
        var hex: UInt32 = 0
        appearance.performAsCurrentDrawingAppearance {
            guard let rgb = NSColor(color).usingColorSpace(.deviceRGB) else { return }
            let red = UInt32((rgb.redComponent * 255).rounded())
            let green = UInt32((rgb.greenComponent * 255).rounded())
            let blue = UInt32((rgb.blueComponent * 255).rounded())
            hex = (red << 16) | (green << 8) | blue
        }
        return hex
    }

    static var entries: [TestEntry] {
        let tests = DesignPaletteTests()
        return [
            TestEntry(suite: suiteName, name: "surfacesResolveToDesignATokensInBothAppearances") {
                try tests.surfacesResolveToDesignATokensInBothAppearances()
            }
        ]
    }
}
