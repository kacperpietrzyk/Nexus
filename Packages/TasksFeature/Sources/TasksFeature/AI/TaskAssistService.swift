import Foundation
import NexusAI
import NexusCore

public struct TaskAssistService: Sendable {
    public enum Action: Sendable, Equatable {
        case refine(field: RefineField)
        case breakIntoSubtasks(maxCount: Int = 5)
        case suggestDueDate(now: Date)
    }

    public enum RefineField: String, Sendable, Equatable {
        case title
        case body
    }

    public struct TaskContext: Sendable, Equatable {
        public let title: String
        public let body: String

        public init(title: String, body: String = "") {
            self.title = title
            self.body = body
        }
    }

    public struct Suggestion: Sendable, Equatable {
        public let action: Action
        public let result: AssistResult

        public init(action: Action, result: AssistResult) {
            self.action = action
            self.result = result
        }
    }

    public enum AssistResult: Sendable, Equatable {
        case refinedText(String)
        case subtaskTitles([String])
        case dueDate(Date)
    }

    public enum AssistError: Error, Equatable, Sendable {
        case emptyRefinement(RefineField)
        case invalidDateFormat(String)
        case pastDueDate(Date, now: Date)
    }

    private let router: AIRouter
    private let connectivity: ConnectivityPreference

    public init(router: AIRouter, connectivity: ConnectivityPreference = .offlineOnly) {
        self.router = router
        self.connectivity = connectivity
    }

    @MainActor
    public func run(_ action: Action, on task: TaskItem) async throws -> AssistResult {
        let context = TaskContext(title: task.title, body: task.body)
        return try await run(action, context: context)
    }

    public func run(_ action: Action, context: TaskContext) async throws -> AssistResult {
        switch action {
        case .refine(let field):
            return .refinedText(try await refine(field: field, context: context))
        case .breakIntoSubtasks(let maxCount):
            return .subtaskTitles(try await breakIntoSubtasks(context: context, maxCount: maxCount))
        case .suggestDueDate(let now):
            return .dueDate(try await suggestDueDate(context: context, now: now))
        }
    }

    public func refine(field: RefineField, context: TaskContext) async throws -> String {
        let target = field == .title ? context.title : context.body
        let prompt = """
            You improve task \(field.rawValue) text for a private local-first productivity app.
            Keep the user's meaning. Fix typos. Tighten phrasing. Do not add facts.
            Preserve the original language.
            Reply with the improved \(field.rawValue) only. No preamble. No quotes.

            Original:
            \(target)
            """
        let text = try await route(prompt: prompt)
        if field == .title, text.isEmpty {
            throw AssistError.emptyRefinement(field)
        }
        return text
    }

    public func breakIntoSubtasks(context: TaskContext, maxCount: Int = 5) async throws -> [String] {
        guard maxCount > 0 else { return [] }
        let prompt = """
            Break this task into at most \(maxCount) concrete, actionable subtasks.
            Use only the task text below. Do not add external facts.
            Preserve the original language.
            Reply with one subtask title per line. No preamble. No bullets. No numbering.

            Task title:
            \(context.title)

            Task body:
            \(context.body)
            """
        let text = try await route(prompt: prompt)
        return Array(parseSubtaskTitles(text).prefix(maxCount))
    }

    public func suggestDueDate(context: TaskContext, now: Date) async throws -> Date {
        let formatter = ISO8601DateFormatter()
        let prompt = """
            Suggest one realistic due date for this task.
            Use only the task text and current timestamp below. Do not add explanation.
            Reply with an ISO8601 timestamp only in this format: YYYY-MM-DDThh:mm:ssZ.

            Current timestamp:
            \(formatter.string(from: now))

            Task title:
            \(context.title)

            Task body:
            \(context.body)
            """
        let text = try await route(prompt: prompt)
        guard let date = Self.parseISO8601(text) else {
            throw AssistError.invalidDateFormat(text)
        }
        guard date >= now else {
            throw AssistError.pastDueDate(date, now: now)
        }
        return date
    }

    private func route(prompt: String) async throws -> String {
        let request = AIRequest(
            prompt: prompt,
            capability: .generate,
            connectivity: connectivity,
            cost: .free,
            providerPreference: .auto
        )
        let response = try await router.route(request)
        return response.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseSubtaskTitles(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { stripListPrefix(String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0.isEmpty == false }
    }

    private func stripListPrefix(_ text: String) -> String {
        var value = text
        if value.hasPrefix("- ") || value.hasPrefix("* ") {
            value.removeFirst(2)
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let range = value.range(
            of: #"^([0-9]+[\.)]|[A-Za-z][\.)])\s+"#,
            options: .regularExpression
        ) {
            value.removeSubrange(range)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseISO8601(_ text: String) -> Date? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let wholeSeconds = ISO8601DateFormatter()
        wholeSeconds.formatOptions = [.withInternetDateTime]
        return wholeSeconds.date(from: value)
    }
}
