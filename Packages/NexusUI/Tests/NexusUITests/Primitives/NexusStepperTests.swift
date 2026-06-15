import SwiftUI
import Testing

@testable import NexusUI

@Suite("NexusStepper")
struct NexusStepperTests {
    @Test("Increment steps up and clamps to the upper bound")
    func incrementClamps() {
        #expect(NexusStepper.incremented(10, by: 5, in: 0...60) == 15)
        #expect(NexusStepper.incremented(58, by: 5, in: 0...60) == 60)  // clamped
        #expect(NexusStepper.incremented(60, by: 5, in: 0...60) == 60)  // already at max
    }

    @Test("Decrement steps down and clamps to the lower bound")
    func decrementClamps() {
        #expect(NexusStepper.decremented(10, by: 5, in: 0...60) == 5)
        #expect(NexusStepper.decremented(2, by: 5, in: 0...60) == 0)  // clamped
        #expect(NexusStepper.decremented(0, by: 5, in: 0...60) == 0)  // already at min
    }

    @Test("Value label appends the unit when present")
    func valueFormatting() {
        #expect(NexusStepper.formatted(value: 15, unit: "min") == "15 min")
        #expect(NexusStepper.formatted(value: 3, unit: nil) == "3")
    }
}
