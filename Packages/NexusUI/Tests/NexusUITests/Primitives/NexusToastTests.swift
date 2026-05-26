import SwiftUI
import Testing

@testable import NexusUI

@Suite("NexusToast")
struct NexusToastTests {
    @MainActor
    @Test("Builds with and without an undo affordance")
    func toastBuilds() {
        _ = NexusToast(icon: "checkmark.circle", message: "Done").body
        _ = NexusToast(icon: "arrow.uturn.backward", message: "Undone", undo: true).body
    }
}
