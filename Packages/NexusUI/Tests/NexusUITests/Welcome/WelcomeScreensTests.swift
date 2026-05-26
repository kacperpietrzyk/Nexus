import SwiftUI
import Testing

@testable import NexusUI

@Suite("WelcomeScreens")
@MainActor
struct WelcomeScreensTests {
    @Test("WhatIsNexusScreen instantiates")
    func whatIsNexusInstantiates() {
        _ = WhatIsNexusScreen()
    }

    @Test("CaptureFlowScreen instantiates")
    func captureFlowInstantiates() {
        _ = CaptureFlowScreen()
    }
}
