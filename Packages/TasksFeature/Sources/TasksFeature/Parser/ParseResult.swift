import Foundation
import NexusCore

/// Output of any `NLParser`. Caller-facing fields cover the standard task
/// metadata (title, dates, priority, tags, project token, recurrence).
/// `confidence` exposes how trustworthy the date/recurrence inference is so
/// the UI can render a "low confidence" chip and the `CompositeNLParser` can
/// decide whether to fall back to the foundation-model augmentation.
public struct ParseResult: Sendable, Equatable {
    public var title: String
    public var dueAt: Date?
    public var startAt: Date?
    public var endAt: Date?
    public var deadlineAt: Date?
    public var priority: TaskPriority?
    public var tags: [String]
    /// Raw `@project` token (sigil stripped, typed case preserved). The parser
    /// never resolves it — the capture/composition layer matches it against
    /// `ProjectRepository` case-insensitively at materialization time.
    public var projectToken: String?
    public var recurrence: String?
    public var unresolvedFragments: [String]
    public var confidence: Float

    public init(
        title: String,
        dueAt: Date? = nil,
        startAt: Date? = nil,
        endAt: Date? = nil,
        deadlineAt: Date? = nil,
        priority: TaskPriority? = nil,
        tags: [String] = [],
        projectToken: String? = nil,
        recurrence: String? = nil,
        unresolvedFragments: [String] = [],
        confidence: Float = 0.0
    ) {
        self.title = title
        self.dueAt = dueAt
        self.startAt = startAt
        self.endAt = endAt
        self.deadlineAt = deadlineAt
        self.priority = priority
        self.tags = tags
        self.projectToken = projectToken
        self.recurrence = recurrence
        self.unresolvedFragments = unresolvedFragments
        self.confidence = confidence
    }

    public static func empty(title: String) -> ParseResult {
        ParseResult(title: title)
    }
}
