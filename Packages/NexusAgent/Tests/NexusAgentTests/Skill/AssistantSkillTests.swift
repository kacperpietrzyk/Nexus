import Foundation
import Testing

@testable import NexusAgent

@Suite struct AssistantSkillTests {
    struct Out: Sendable, Equatable { let n: Int }

    @Test func contractDecodesValidAndThrowsOnInvalid() throws {
        let contract = OutputContract<Out>(schemaDescription: "{n:int}") { text in
            guard let n = Int(text.trimmingCharacters(in: .whitespaces)) else {
                throw OutputContractError.invalid(reason: "not an int")
            }
            return Out(n: n)
        }
        #expect(try contract.decode("42") == Out(n: 42))
        #expect(throws: OutputContractError.self) { try contract.decode("abc") }
    }

    @Test func skillDefaultsToSingleIterationNoTools() {
        let skill = AssistantSkill(
            id: "x",
            systemPrompt: "p",
            contextRecipe: ContextRecipe(),
            output: OutputContract<Out>(schemaDescription: "") { _ in Out(n: 0) })
        #expect(skill.maxIterations == 1)
        #expect(skill.allowsToolCalling == false)
        #expect(skill.toolNames.isEmpty)
    }
}
