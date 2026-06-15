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

    /// Boxed `ModelContainer` for whole-vault walks (the `export.bundle` tool
    /// opens its own `ModelContext` per container, mirroring `MarkdownExporter`).
    /// `nil` when no container was injected — export tools then throw
    /// `.internalError`. Defaulted nil so non-production callers (e.g. older
    /// fixtures) keep compiling without supplying one.
    public let modelContainer: ModelContainerRef?

    /// On-demand `CommentRepository` backed by the same `ModelContext` as `taskRepository`.
    @MainActor public var commentRepository: CommentRepository {
        CommentRepository(context: modelContext.context)
    }

    /// On-demand `NoteRepository` backed by the same `ModelContext` as `taskRepository`.
    /// The task repository is injected so the checkbox→Task seam (§7) drives the real
    /// task lifecycle (recurrence, notifications) when a todo block is toggled via MCP,
    /// rather than the pure-core direct-status-flip fallback.
    @MainActor public var noteRepository: NoteRepository {
        NoteRepository(
            context: modelContext.context,
            tasks: taskRepository.repository,
            now: now
        )
    }

    /// On-demand `ProjectRepository` (Projects tier, spec §10) backed by the same
    /// `ModelContext` as `taskRepository`.
    @MainActor public var projectRepository: ProjectRepository {
        ProjectRepository(context: modelContext.context, now: now)
    }

    /// On-demand `LabelRepository` (Projects tier, spec §7 / §10) — owns the
    /// single-select policy, the system-label seed, and the agent-queue query.
    @MainActor public var labelRepository: LabelRepository {
        LabelRepository(context: modelContext.context, now: now)
    }

    /// On-demand `LinkRepository` (Projects tier, spec §9 / §10) for `blocks`
    /// dependency edges.
    @MainActor public var linkRepository: LinkRepository {
        LinkRepository(context: modelContext.context)
    }

    /// On-demand `CycleRepository` (Tranche 2, Plan A) backed by the same
    /// `ModelContext` as `taskRepository`. Used today only by
    /// `AgentEndpointValidator` (edge tools accept any `ItemKind`, so a cycle
    /// endpoint must be existence-checked); cycle agent tools land in Plan C.
    @MainActor public var cycleRepository: CycleRepository {
        CycleRepository(context: modelContext.context, now: now)
    }

    /// On-demand read-only `ActivityEntryRepository` reader (Tranche 2 Plan B,
    /// spec §6.3) backed by the same `ModelContext` as `taskRepository`. Tools
    /// only READ the audit log — they never insert rows (invariant I-B1).
    @MainActor public var activityEntryRepository: ActivityEntryRepository {
        ActivityEntryRepository(context: modelContext.context, now: now)
    }

    /// On-demand `SavedFilterRepository` backed by the same `ModelContext`.
    @MainActor public var savedFilterRepository: SavedFilterRepository {
        SavedFilterRepository(context: modelContext.context, now: now)
    }

    /// On-demand `PersonRepository` (People/Contacts module, spec §7) backed by the
    /// same `ModelContext` as `taskRepository`. CRUD + dedup/upsert + atomic merge +
    /// graph aggregation; the only `task ↔ person` edge it emits is `.mentions`
    /// (invariant I1 — a `Person` is never a task assignee).
    @MainActor public var personRepository: PersonRepository {
        PersonRepository(context: modelContext.context, now: now)
    }

    /// On-demand `OrganizationRepository` backed by the same `ModelContext`.
    @MainActor public var organizationRepository: OrganizationRepository {
        OrganizationRepository(context: modelContext.context, now: now)
    }

    /// On-demand `ProjectKeyDateRepository` backed by the same `ModelContext`.
    @MainActor public var projectKeyDateRepository: ProjectKeyDateRepository {
        ProjectKeyDateRepository(context: modelContext.context, now: now)
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
        heroBriefService: HeroBriefServiceRef? = nil,
        modelContainer: ModelContainerRef? = nil
    ) {
        self.modelContext = modelContext
        self.taskRepository = taskRepository
        self.searchIndex = searchIndex
        self.now = now
        self.nlParser = nlParser
        self.heroBriefService = heroBriefService
        self.modelContainer = modelContainer
    }
}

/// Boxed @MainActor reference to ModelContainer (ModelContainer is Sendable, but
/// keep the same boxed shape as `ModelContextRef` for consistency at call sites).
public struct ModelContainerRef: @unchecked Sendable {
    private let stored: ModelContainer

    @MainActor public var container: ModelContainer { stored }

    @MainActor public init(_ container: ModelContainer) {
        self.stored = container
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
