import SwiftUI
import Testing

@testable import NexusUI

@Suite("NexusCheckbox v4")
struct NexusCheckboxTests {
    @MainActor
    @Test("Constants match canvas checkbox geometry")
    func constants() {
        #expect(NexusCheckbox.side == 16)
        #expect(NexusCheckbox.cornerRadius == 5)
    }

    @MainActor
    @Test("Builds with unchecked binding")
    func buildsUnchecked() {
        let model = CheckboxModel()
        let checkbox = NexusCheckbox(
            isChecked: Binding(
                get: { model.isChecked },
                set: { model.isChecked = $0 }
            ))

        #expect(checkbox.isChecked == false)
        #expect(checkbox.borderColor.resolvedRGBA == NexusColor.Line.strong.resolvedRGBA)
        _ = checkbox.body
    }

    @MainActor
    @Test("Binding toggles through projected binding")
    func bindingToggles() {
        let model = CheckboxModel()
        let binding = Binding(
            get: { model.isChecked },
            set: { model.isChecked = $0 }
        )

        binding.wrappedValue.toggle()
        let checkbox = NexusCheckbox(isChecked: binding)

        #expect(model.isChecked)
        #expect(checkbox.isChecked)
        // Checked state uses a faint white rim; unchecked uses Line.strong.
        #expect(checkbox.borderColor.resolvedRGBA == Color.white.opacity(0.16).resolvedRGBA)
    }
}

@MainActor
private final class CheckboxModel {
    var isChecked = false
}
