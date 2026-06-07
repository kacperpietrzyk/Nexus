import Foundation
import NexusCore
import SwiftData

/// `tasks.estimateDuration` (spec §5 / §12): compute and return the duration
/// estimate for a task WITHOUT persisting anything. The estimate cascade
/// (explicit → history → fallback) runs against the live completed-task corpus.
/// Read-only by contract — it never writes `estimatedDurationSeconds` (a user
/// override does that elsewhere, spec §5).
public struct TasksEstimateDurationTool: AgentTool {
    public let name = "tasks.estimate_duration"
    public let description =
        "Estimates how long a task will take, in seconds, with a confidence in [0,1]. "
        + "Read-only: it computes the estimate from heuristics and completion history "
        + "and never persists anything."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "task_id": .string(description: "Task UUID to estimate.")
        ],
        required: ["task_id"]
    )

    private let estimator: any DurationEstimator

    public init(estimator: any DurationEstimator = HeuristicDurationEstimator()) {
        self.estimator = estimator
    }

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["task_id"], field: "task_id")
        let modelContext = context.modelContext.context

        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate<TaskItem> { task in
                task.id == id && task.deletedAt == nil
            }
        )
        guard let task = try modelContext.fetch(descriptor).first else {
            throw AgentError.notFound("Task not found: \(id.uuidString)")
        }

        let history = try ScheduleToolSupport.history(context: modelContext)
        let estimate = estimator.estimate(for: task, history: history)
        return try TasksToolJSON.encode(DurationEstimateDTO(taskID: task.id, estimate: estimate))
    }
}
