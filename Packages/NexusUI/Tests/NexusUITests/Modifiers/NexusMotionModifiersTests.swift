import SwiftUI
import Testing

@testable import NexusUI

@MainActor
@Test func motionModifiersAttach() {
    _ = Color.clear.nexusAppear(0)
    _ = Color.clear.nexusReveal(2)
    _ = Color.clear.nexusPressable()
    _ = Color.clear.nexusOverlayEnter()
    _ = AnyTransition.nexusView
    _ = AnyTransition.nexusToast
}
