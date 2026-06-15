import Foundation
import NexusCore  // JSONValue, DateMath, DateExtracting

public enum PanelTaskSuggestDueSkill {
    public struct DueHint: Decodable, Sendable, Equatable {
        public let whenHint: String
        public let estMinutes: Int?
    }

    public static let outputContract = OutputContract<DueHint>(
        schemaDescription: #"{"whenHint":string,"estMinutes"?:int}"#
    ) { text in
        let step1 = text.replacingOccurrences(of: "```json", with: "")
        let step2 = step1.replacingOccurrences(of: "```", with: "")
        let cleaned = step2.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8) else {
            throw OutputContractError.invalid(reason: "expected JSON matching the due hint contract")
        }
        guard let decoded = try? JSONDecoder().decode(DueHint.self, from: data) else {
            throw OutputContractError.invalid(reason: "expected JSON matching the due hint contract")
        }
        guard !decoded.whenHint.isEmpty else {
            throw OutputContractError.invalid(reason: "empty whenHint")
        }
        return decoded
    }

    public static func skill() -> AssistantSkill<DueHint> {
        AssistantSkill(
            id: "panel.task_suggest_due",
            systemPrompt: """
                Suggest when this task should be due. Return a JSON object with \
                "whenHint" (e.g. "tomorrow", "friday", "next week") and optional \
                "estMinutes" (estimated effort in minutes). No markdown fences.
                """,
            contextRecipe: ContextRecipe(tokenBudget: 1_000),
            output: outputContract,
            maxIterations: 1,
            allowsToolCalling: false)
    }
}

@MainActor
public final class PanelTaskSuggestDueCoordinator {
    private let runner: SkillRunner
    private let dateMath: DateMath

    public init(runner: SkillRunner, dateMath: DateMath = DateMath()) {
        self.runner = runner
        self.dateMath = dateMath
    }

    public func suggestDue(
        taskID: UUID,
        title: String,
        focus: ContextFocus,
        now: Date = .now
    ) async throws -> Proposal {
        let result = try await runner.run(
            PanelTaskSuggestDueSkill.skill(),
            focus: focus,
            userText: "Task: \(title)",
            now: now)
        let hint = result.output.whenHint
        let resolvedDate = await dateMath.resolve(hint, now: now, locale: .current)
        let dueDate = resolvedDate ?? dateMath.startOfDay(dateMath.addDays(1, to: now))
        let iso = ISO8601DateFormatter()
        let dueDateString = iso.string(from: dueDate)
        let args: JSONValue = .object([
            "task_id": .string(taskID.uuidString),
            "patch": .object(["due_date": .string(dueDateString)]),
        ])
        let previewSummary = "Set due date to \(dueDateString) (hint: \"\(hint)\")"
        return Proposal(
            rationale: "Suggested due date based on hint: \"\(hint)\".",
            mutations: [PendingMutation(toolName: "tasks.update", arguments: args)],
            previews: [ProposalPreview(summary: previewSummary)])
    }
}
