import Foundation
import NexusCore
import SwiftData

/// Dependency container passed to every `AgentTool.call`. Built by the app composition
/// root (`AgentToolBootstrap`). Tools read what they need; new tools add new fields here.
public struct AgentContext: Sendable {
    public let modelContext: ModelContextRef
    public let taskRepository: TaskItemRepositoryRef
    public let searchIndex: SearchIndex
    public let now: @Sendable () -> Date

    /// On-demand `CommentRepository` backed by the same `ModelContext` as `taskRepository`.
    @MainActor public var commentRepository: CommentRepository {
        CommentRepository(context: modelContext.context)
    }

    /// TasksFeature-specific helpers (NL parser + hero brief). Only populated when
    /// the consumer links `NexusAgentToolsExtras`. Tools that need these check non-nil.
    public let nlParser: AnyNLParserRef?
    public let heroBriefService: HeroBriefServiceRef?

    public init(
        modelContext: ModelContextRef,
        taskRepository: TaskItemRepositoryRef,
        searchIndex: SearchIndex,
        now: @escaping @Sendable () -> Date,
        nlParser: AnyNLParserRef? = nil,
        heroBriefService: HeroBriefServiceRef? = nil
    ) {
        self.modelContext = modelContext
        self.taskRepository = taskRepository
        self.searchIndex = searchIndex
        self.now = now
        self.nlParser = nlParser
        self.heroBriefService = heroBriefService
    }
}

/// Boxed @MainActor reference to ModelContext (ModelContext is not Sendable).
public struct ModelContextRef: @unchecked Sendable {
    private let storedContext: ModelContext

    @MainActor public var context: ModelContext { storedContext }

    @MainActor public init(_ context: ModelContext) {
        self.storedContext = context
    }
}

/// Boxed @MainActor reference to TaskItemRepository.
public struct TaskItemRepositoryRef: @unchecked Sendable {
    private let storedRepository: TaskItemRepository

    @MainActor public var repository: TaskItemRepository { storedRepository }

    @MainActor public init(_ repository: TaskItemRepository) {
        self.storedRepository = repository
    }
}

/// Type-erased boxed reference to a TasksFeature CompositeNLParser-like actor.
/// Concrete type lives in NexusAgentToolsExtras to avoid forcing TasksFeature dep.
public struct AnyNLParserRef: @unchecked Sendable {
    private let parseImpl: @MainActor @Sendable (_ input: String, _ locale: Locale, _ now: Date) async -> Any

    public init(parse: @escaping @MainActor @Sendable (String, Locale, Date) async -> Any) {
        self.parseImpl = parse
    }

    @MainActor public func parse(_ input: String, locale: Locale, now: Date) async -> Any {
        await parseImpl(input, locale, now)
    }
}

/// Type-erased reference to TasksFeature HeroBriefService.
public struct HeroBriefServiceRef: @unchecked Sendable {
    private let briefImpl: @MainActor @Sendable (_ context: ModelContext, _ now: Date) async -> Any

    public init(brief: @escaping @MainActor @Sendable (ModelContext, Date) async -> Any) {
        self.briefImpl = brief
    }

    @MainActor public func brief(context: ModelContext, now: Date) async -> Any {
        await briefImpl(context, now)
    }
}
