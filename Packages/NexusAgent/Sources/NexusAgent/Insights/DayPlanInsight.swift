import Foundation

public enum DayPlanInsight {
    private static func decodePlanText(_ text: String) throws -> String {
        let step1 = text.replacingOccurrences(of: "```", with: "")
        let cleaned = step1.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw OutputContractError.invalid(reason: "empty day plan")
        }
        return cleaned
    }

    private static let outputContract = OutputContract<String>(
        schemaDescription: "1–2 plain sentences suggesting task ordering for today. No markdown.",
        decode: decodePlanText)

    /// Read-only text skill: fenced-tolerant, like PanelDailyBriefSkill.
    public static func skill() -> AssistantSkill<String> {
        AssistantSkill(
            id: "insight.day_plan",
            systemPrompt: """
                You suggest a focus order for a personal task app user's day. \
                Use ONLY the numbers and tasks given. Never invent items. \
                1–2 sentences, plain prose, no markdown.
                """,
            contextRecipe: ContextRecipe(
                repoSlices: [.tasksDueWithin(days: 1), .overdueTasks],
                tokenBudget: 1_500),
            output: outputContract,
            maxIterations: 1,
            allowsToolCalling: false)
    }

    /// Runs the skill and wraps the result in an advice-only Proposal (no mutations).
    @MainActor
    public static func proposal(
        runner: SkillRunner,
        summaryNumbers: String,
        focus: ContextFocus,
        now: Date
    ) async throws -> Proposal {
        let result = try await runner.run(
            skill(),
            focus: focus,
            userText: "Today's numbers: \(summaryNumbers)",
            now: now)
        return Proposal(rationale: result.output, mutations: [], previews: [])
    }
}
