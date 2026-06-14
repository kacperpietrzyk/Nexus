import Foundation
import NexusCore  // JSONValue

public enum PanelTaskRefineSkill {
    public enum Field: String, Sendable { case title, body }

    public static let outputContract = OutputContract<String>(
        schemaDescription: "The improved text only. No quotes, no preamble, no markdown fences."
    ) { text in
        let step1 = text.replacingOccurrences(of: "```", with: "")
        let cleaned = step1.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw OutputContractError.invalid(reason: "empty refinement") }
        return cleaned
    }

    public static func titleSystemPrompt() -> String {
        "Rewrite the task title to be concise, specific, and action-oriented. Return only the new title."
    }

    public static func bodySystemPrompt() -> String {
        "Improve the task notes for clarity. Keep the user's intent. Return only the improved notes."
    }

    public static func skill(field: Field) -> AssistantSkill<String> {
        let prompt = field == .title ? titleSystemPrompt() : bodySystemPrompt()
        return AssistantSkill(
            id: "panel.task_refine_\(field.rawValue)",
            systemPrompt: prompt,
            contextRecipe: ContextRecipe(tokenBudget: 1_000),
            output: outputContract,
            maxIterations: 1,
            allowsToolCalling: false)
    }
}

@MainActor
public final class PanelTaskRefineCoordinator {
    private let runner: SkillRunner
    public init(runner: SkillRunner) { self.runner = runner }

    public func refine(
        field: PanelTaskRefineSkill.Field,
        taskID: UUID,
        currentText: String,
        focus: ContextFocus,
        now: Date = .now
    ) async throws -> Proposal {
        let result = try await runner.run(
            PanelTaskRefineSkill.skill(field: field),
            focus: focus,
            userText: "Current \(field.rawValue):\n\(currentText)",
            now: now)
        let patchKey = field == .title ? "title" : "notes"
        let args: JSONValue = .object([
            "task_id": .string(taskID.uuidString),
            "patch": .object([patchKey: .string(result.output)]),
        ])
        let previewSummary = "\(field.rawValue): \"\(currentText)\" → \"\(result.output)\""
        return Proposal(
            rationale: "Refined \(field.rawValue).",
            mutations: [PendingMutation(toolName: "tasks.update", arguments: args)],
            previews: [ProposalPreview(summary: previewSummary)])
    }
}
