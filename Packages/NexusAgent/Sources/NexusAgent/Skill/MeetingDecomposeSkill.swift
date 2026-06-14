import Foundation
import NexusCore  // JSONValue, CalendarEvent, CalendarPreferences, SlotScheduler, WorkloadAnalyzer, CapacityModel, ScheduledItem

public enum MeetingDecomposeSkill {
    public struct CandidateTask: Sendable, Equatable, Decodable {
        public let title: String
        public let estMinutes: Int
        public let suggestedDay: String?
    }

    public struct Decomposed: Sendable, Equatable, Decodable {
        public let tasks: [CandidateTask]
    }

    public static let outputContract = OutputContract<Decomposed>(
        schemaDescription: #"{"tasks":[{"title":string,"estMinutes":int,"suggestedDay"?:"YYYY-MM-DD"}]}"#
    ) { text in
        // Tolerate fenced code blocks the model may add.
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8) else {
            throw OutputContractError.invalid(reason: "expected JSON matching the tasks contract")
        }
        guard let decoded = try? JSONDecoder().decode(Decomposed.self, from: data) else {
            throw OutputContractError.invalid(reason: "expected JSON matching the tasks contract")
        }
        guard !decoded.tasks.isEmpty else {
            throw OutputContractError.invalid(reason: "no tasks extracted")
        }
        return decoded
    }

    public static func skill(recipe: ContextRecipe) -> AssistantSkill<Decomposed> {
        AssistantSkill(
            id: "meeting.decompose",
            systemPrompt: """
            You decompose a meeting summary into concrete candidate tasks for a personal task manager.
            Extract only actionable items. Estimate minutes conservatively. Do not invent dates.
            """,
            contextRecipe: recipe,
            output: outputContract,
            maxIterations: 1,
            allowsToolCalling: false)
    }
}

@MainActor
public final class MeetingDecomposeCoordinator {
    private let runner: SkillRunner
    private let scheduler: SlotScheduler  // NexusCore (named SlotScheduler to avoid the existing `actor Scheduler`)
    private let workload: WorkloadAnalyzer
    private let capacity: CapacityModel
    private let prefs: CalendarPreferences
    private let events: [CalendarEvent]
    private let now: Date

    public init(
        runner: SkillRunner,
        scheduler: SlotScheduler,
        workload: WorkloadAnalyzer,
        capacity: CapacityModel,
        prefs: CalendarPreferences,
        events: [CalendarEvent],
        now: Date
    ) {
        self.runner = runner
        self.scheduler = scheduler
        self.workload = workload
        self.capacity = capacity
        self.prefs = prefs
        self.events = events
        self.now = now
    }

    public func decompose(
        summary: String,
        focus: ContextFocus,
        recipe: ContextRecipe = ContextRecipe(
            includeEntity: true,
            linkGraphDepth: 1,
            repoSlices: [.tasksDueWithin(days: 7)],
            ragQuery: nil,
            tokenBudget: 3_000)
    ) async throws -> Proposal {
        let skill = MeetingDecomposeSkill.skill(recipe: recipe)
        let result = try await runner.run(skill, focus: focus, userText: summary, now: now)

        // Step 5: skeleton slots each candidate into a free window; flag overload.
        let iso = ISO8601DateFormatter()
        var mutations: [PendingMutation] = []
        var previews: [ProposalPreview] = []
        var scheduledItems: [ScheduledItem] = []
        let days = (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: now) }

        for task in result.output.tasks {
            let slot = scheduler.slot(
                durationMinutes: task.estMinutes,
                within: days,
                events: events,
                prefs: prefs,
                after: now)
            var args: [String: JSONValue] = ["title": .string(task.title)]
            if let slot {
                args["due_date"] = .string(iso.string(from: slot.start))
            }
            mutations.append(PendingMutation(toolName: "tasks.create", arguments: .object(args)))
            let when = slot.map { " → \(iso.string(from: $0.start))" } ?? " (unscheduled)"
            previews.append(ProposalPreview(summary: "Create: \(task.title) [\(task.estMinutes)m]\(when)"))
            if let slot {
                scheduledItems.append(ScheduledItem(id: UUID(), durationMinutes: task.estMinutes, day: slot.start))
            }
        }

        let loads = workload.analyze(tasks: scheduledItems, events: events, days: days, capacity: capacity)
        let overloaded = loads.filter { $0.isOverloaded }
        var rationale = "Extracted \(result.output.tasks.count) task(s) from the meeting summary."
        if !overloaded.isEmpty {
            rationale += " Warning: \(overloaded.count) day(s) look overloaded."
        }

        return Proposal(rationale: rationale, mutations: mutations, previews: previews)
    }
}
