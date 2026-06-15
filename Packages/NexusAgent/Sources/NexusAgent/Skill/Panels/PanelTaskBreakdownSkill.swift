import Foundation
import NexusCore  // JSONValue

public enum PanelTaskBreakdownSkill {
    private struct SubtaskList: Decodable {
        let subtasks: [String]
    }

    public static let outputContract = OutputContract<[String]>(
        schemaDescription: #"{"subtasks":[string]}"#
    ) { text in
        let step1 = text.replacingOccurrences(of: "```json", with: "")
        let step2 = step1.replacingOccurrences(of: "```", with: "")
        let cleaned = step2.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8) else {
            throw OutputContractError.invalid(reason: "expected JSON matching the subtasks contract")
        }
        guard let decoded = try? JSONDecoder().decode(SubtaskList.self, from: data) else {
            throw OutputContractError.invalid(reason: "expected JSON matching the subtasks contract")
        }
        guard !decoded.subtasks.isEmpty else {
            throw OutputContractError.invalid(reason: "no subtasks extracted")
        }
        return decoded.subtasks
    }

    public static func skill() -> AssistantSkill<[String]> {
        AssistantSkill(
            id: "panel.task_breakdown",
            systemPrompt: """
                Break the given task into 2–5 concrete, actionable subtasks. \
                Return JSON: {"subtasks":["subtask 1","subtask 2",...]}. No markdown fences.
                """,
            contextRecipe: ContextRecipe(tokenBudget: 1_000),
            output: outputContract,
            maxIterations: 1,
            allowsToolCalling: false)
    }
}

@MainActor
public final class PanelTaskBreakdownCoordinator {
    private let runner: SkillRunner
    public init(runner: SkillRunner) { self.runner = runner }

    public func breakdown(
        taskID: UUID,
        title: String,
        focus: ContextFocus,
        now: Date = .now
    ) async throws -> Proposal {
        let result = try await runner.run(
            PanelTaskBreakdownSkill.skill(),
            focus: focus,
            userText: "Task to break down: \(title)",
            now: now)
        let mutations = result.output.map { subtaskTitle -> PendingMutation in
            let args: JSONValue = .object([
                "title": .string(subtaskTitle),
                "parent_id": .string(taskID.uuidString),
            ])
            return PendingMutation(toolName: "tasks.create", arguments: args)
        }
        let previews = result.output.map { ProposalPreview(summary: "Create subtask: \($0)") }
        return Proposal(
            rationale: "Broke '\(title)' into \(result.output.count) subtask(s).",
            mutations: mutations,
            previews: previews)
    }
}
