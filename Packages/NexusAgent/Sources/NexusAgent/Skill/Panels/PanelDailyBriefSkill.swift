import Foundation

public enum PanelDailyBriefSkill {
    /// Read-only text. The decode tolerates fenced blocks and just returns the trimmed string.
    public static let outputContract = OutputContract<String>(
        schemaDescription: "1–2 plain sentences summarising the day. No markdown, no lists."
    ) { text in
        let step1 = text.replacingOccurrences(of: "```", with: "")
        let cleaned = step1.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw OutputContractError.invalid(reason: "empty brief") }
        return cleaned
    }

    public static func skill() -> AssistantSkill<String> {
        AssistantSkill(
            id: "panel.daily_brief",
            systemPrompt: """
                You write a short, friendly daily brief for a personal task app. Use ONLY the numbers \
                and titles given. Never invent counts. 1–2 sentences, plain prose.
                """,
            contextRecipe: ContextRecipe(
                repoSlices: [.tasksDueWithin(days: 1), .overdueTasks],
                tokenBudget: 1_500),
            output: outputContract,
            maxIterations: 1,
            allowsToolCalling: false)
    }
}

@MainActor
public final class PanelDailyBriefCoordinator {
    private let runner: SkillRunner
    public init(runner: SkillRunner) { self.runner = runner }

    /// `summaryNumbers` = caller-computed counts (incl. calendar) folded into userText.
    public func brief(summaryNumbers: String, focus: ContextFocus, now: Date = .now) async throws -> String {
        let result = try await runner.run(
            PanelDailyBriefSkill.skill(),
            focus: focus,
            userText: "Today's numbers: \(summaryNumbers)",
            now: now)
        return result.output
    }
}
