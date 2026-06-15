import SwiftUI
import Testing

@testable import NexusUI

@Suite("LiquidSelect")
struct LiquidSelectTests {

    private func select(selection: String) -> LiquidSelect<String> {
        LiquidSelect(
            [
                .init(id: "todo", label: "To Do"),
                .init(id: "doing", label: "Doing"),
                .init(id: "done", label: "Done"),
            ],
            selection: .constant(selection)
        )
    }

    @Test("selectedOption resolves the bound id to its option")
    func selectedOptionResolves() {
        let field = select(selection: "doing")
        #expect(field.selectedOption?.id == "doing")
        #expect(field.selectedOption?.label == "Doing")
    }

    @Test("Options preserve their order and identity")
    func optionOrder() {
        let field = select(selection: "todo")
        #expect(field.options.map(\.id) == ["todo", "doing", "done"])
        #expect(field.options.map(\.label) == ["To Do", "Doing", "Done"])
    }

    @Test("Unknown selection resolves to no option")
    func unknownSelection() {
        let field = select(selection: "archived")
        #expect(field.selectedOption == nil)
    }

    @Test("Placeholder defaults to empty and is stored when provided")
    func placeholder() {
        #expect(select(selection: "todo").placeholder.isEmpty)
        let withPlaceholder = LiquidSelect(
            [LiquidSelectOption(id: "todo", label: "To Do")],
            selection: .constant("todo"),
            placeholder: "Choose…"
        )
        #expect(withPlaceholder.placeholder == "Choose…")
    }

    @Test("Option stores its optional system image")
    func optionImage() {
        let option = LiquidSelectOption(id: "todo", label: "To Do", systemImage: "circle")
        #expect(option.systemImage == "circle")
        #expect(LiquidSelectOption(id: "done", label: "Done").systemImage == nil)
    }
}
