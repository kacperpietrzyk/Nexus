import Foundation
import Testing
@testable import NexusAgent

@Suite struct ContextRecipeTests {
    @Test func focusEquatableAndOptional() {
        let id = UUID()
        let a = ContextFocus(primaryID: id, kind: "meeting", freeText: "Q3")
        let b = ContextFocus(primaryID: id, kind: "meeting", freeText: "Q3")
        #expect(a == b)
        #expect(ContextFocus(primaryID: nil, kind: nil, freeText: nil) == ContextFocus())
    }

    @Test func recipeCarriesSlicesAndBudget() {
        let recipe = ContextRecipe(
            includeEntity: true,
            linkGraphDepth: 1,
            repoSlices: [.tasksDueWithin(days: 7), .overdueTasks],
            ragQuery: RagQuerySpec(query: "decision", limit: 5),
            tokenBudget: 2_000
        )
        #expect(recipe.repoSlices.count == 2)
        #expect(recipe.tokenBudget == 2_000)
    }
}
