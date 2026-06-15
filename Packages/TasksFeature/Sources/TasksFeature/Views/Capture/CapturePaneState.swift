import Foundation
import NexusCore
import Observation

/// View-model for `CapturePane`. Owns the input string + the last `ParseResult`
/// + the parser invocation. Spec §10 line 620 calls for a 50ms keystroke
/// debounce on the handcoded pass; the FM trigger is implicit because the
/// cascade gates FM on confidence already. Commits insert via a caller-supplied
/// closure so the view-model stays repository-agnostic and tests can inject a
/// recorder.
@MainActor
@Observable
public final class CapturePaneState {

    public var input: String = ""
    public private(set) var lastResult: ParseResult?

    private let parser: any NLParser
    private let locale: Locale
    private let nowProvider: @Sendable () -> Date
    private let debounce: Duration
    private let projectResolver: (@MainActor (String) -> UUID?)?
    private var pendingTask: _Concurrency.Task<Void, Never>?

    public init(
        parser: any NLParser,
        locale: Locale = .current,
        nowProvider: @escaping @Sendable () -> Date = { .now },
        debounce: Duration = .milliseconds(50),
        projectResolver: (@MainActor (String) -> UUID?)? = nil
    ) {
        self.parser = parser
        self.locale = locale
        self.nowProvider = nowProvider
        self.debounce = debounce
        self.projectResolver = projectResolver
    }

    /// Re-runs the parser with the new input. Call from SwiftUI
    /// `.onChange(of: input)`. The 50ms wait coalesces rapid keystrokes;
    /// cancellation drops superseded parses.
    public func handleInputChange(_ newInput: String) async {
        if self.input != newInput {
            self.input = newInput
        }
        let trimmed = newInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            self.lastResult = nil
            pendingTask?.cancel()
            return
        }
        pendingTask?.cancel()
        let captured = nowProvider()
        let debounce = self.debounce
        let task = _Concurrency.Task { [parser, locale, trimmed] in
            if debounce > .zero {
                try? await _Concurrency.Task.sleep(for: debounce)
            }
            if _Concurrency.Task.isCancelled { return }
            let result = await parser.parse(trimmed, locale: locale, now: captured)
            if !_Concurrency.Task.isCancelled {
                await MainActor.run { self.lastResult = result }
            }
        }
        pendingTask = task
        await task.value
    }

    /// Builds a `TaskItem` from `lastResult` and hands it to the inserter.
    /// Resets the input string only after the inserter succeeds, so a failed
    /// persist (e.g. `context.save()` throws) leaves the user's text and parse
    /// intact instead of silently discarding them.
    public func commit(insert: @MainActor (TaskItem) throws -> Void) async throws {
        guard let result = lastResult else { return }
        let task = TaskItem(
            title: result.title,
            dueAt: result.dueAt,
            startAt: result.startAt,
            endAt: result.endAt,
            deadlineAt: result.deadlineAt,
            priority: result.priority ?? .none,
            tags: result.tags,
            recurrenceRule: result.recurrence,
            projectID: result.projectToken.flatMap { projectResolver?($0) }
        )
        try insert(task)
        self.input = ""
        self.lastResult = nil
    }
}
