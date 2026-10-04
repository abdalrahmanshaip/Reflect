import Foundation
@testable import ReflectLib

/// Regression coverage for the shared custom-row hover contract: disabled
/// controls never expose or retain a clickable hover state.
struct HoverAffordanceTests {
    static let suiteName = "HoverAffordanceTests"

    func disabledControlsDoNotExposeHoverState() throws {
        var state = ReflectHoverState()
        state.update(isHovered: true, isEnabled: false)
        try expectFalse(state.isHovered, "disabled controls must not look clickable")

        state.update(isHovered: true, isEnabled: true)
        try expectTrue(state.isHovered, "enabled controls should expose hover state")

        state.update(isHovered: false, isEnabled: true)
        try expectFalse(state.isHovered, "leaving a row must clear its hover state")

        state.update(isHovered: true, isEnabled: true)
        state.update(isHovered: false, isEnabled: false)
        try expectFalse(state.isHovered, "disabling a hovered control must clear the state")
    }

    static var entries: [TestEntry] {
        let tests = HoverAffordanceTests()
        return [
            TestEntry(suite: suiteName, name: "disabledControlsDoNotExposeHoverState") {
                try tests.disabledControlsDoNotExposeHoverState()
            }
        ]
    }
}
