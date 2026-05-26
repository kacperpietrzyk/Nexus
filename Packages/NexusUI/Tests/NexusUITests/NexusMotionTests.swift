import SwiftUI
import Testing

@testable import NexusUI

@Test func motionConstantsExist() {
    #expect(NexusMotion.staggerStep == 0.055)
    #expect(NexusMotion.breathePeriod == 2.4)
    _ = NexusMotion.standard
    _ = NexusMotion.hover
    _ = NexusMotion.enter
    _ = NexusMotion.exit
    _ = NexusMotion.press
    _ = NexusMotion.nav
}
