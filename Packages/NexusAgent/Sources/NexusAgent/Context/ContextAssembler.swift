import Foundation
import NexusAgentTools
import NexusCore
import SwiftData

@MainActor
public final class ContextAssembler {
    private let agentContext: AgentContext
    private let retriever: any RagRetriever

    public init(agentContext: AgentContext, retriever: any RagRetriever) {
        self.agentContext = agentContext; self.retriever = retriever
    }

    public func assemble(_ recipe: ContextRecipe, focus: ContextFocus, now: Date) async -> AssembledContext {
        var sections: [AssembledContext.Section] = []

        if recipe.includeEntity, let entity = renderEntity(focus) {
            sections.append(entity)
        }
        if recipe.linkGraphDepth > 0, let links = renderLinkSection(focus: focus, depth: recipe.linkGraphDepth) {
            sections.append(links)
        }
        // Live tasks (deletedAt == nil) are fetched at most once per assembly and
        // reused across every task-backed slice (.tasksDueWithin, .overdueTasks),
        // instead of re-fetching the whole TaskItem table per slice. Lazy: stays
        // nil — and the fetch never runs — when no slice needs tasks.
        var liveTasks: [TaskItem]?
        for slice in recipe.repoSlices {
            if let section = renderSlice(slice, now: now, liveTasks: &liveTasks) { sections.append(section) }
        }
        if let rag = recipe.ragQuery, let section = await renderRagSection(rag) {
            sections.append(section)
        }

        return truncate(sections, to: recipe.tokenBudget)
    }

    // MARK: rendering

    /// Resolves the focus's `(kind, id)` and renders its Link-graph neighbours, if any.
    private func renderLinkSection(focus: ContextFocus, depth: Int) -> AssembledContext.Section? {
        guard let primary = focus.primaryID, let kindRaw = focus.kind,
            let kind = ItemKind(rawValue: kindRaw)
        else { return nil }
        return renderLinkNeighbours(id: primary, kind: kind, depth: depth)
    }

    /// Runs hybrid RAG for the recipe query; nil when the retriever fails or returns nothing.
    private func renderRagSection(_ rag: RagQuerySpec) async -> AssembledContext.Section? {
        guard let hits = try? await retriever.retrieve(query: rag.query, scope: "global", limit: rag.limit),
            !hits.isEmpty
        else { return nil }
        return AssembledContext.Section(
            title: "Relevant notes (\(hits.count))",
            body: hits.map { "- \($0.title): \($0.snippet)" }.joined(separator: "\n"))
    }

    private func renderEntity(_ focus: ContextFocus) -> AssembledContext.Section? {
        guard let id = focus.primaryID, let kindRaw = focus.kind, let kind = ItemKind(rawValue: kindRaw) else { return nil }
        switch kind {
        case .task:
            guard
                let t = try? agentContext.modelContext.context.fetch(
                    FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
                ).first
            else { return nil }
            return .init(title: "Focus task", body: "\(t.title)")
        case .project:
            guard
                let p = try? agentContext.modelContext.context.fetch(
                    FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })
                ).first
            else { return nil }
            return .init(title: "Focus project", body: "\(p.name) [\(p.statusRaw)]")
        case .person:
            guard
                let p = try? agentContext.modelContext.context.fetch(
                    FetchDescriptor<Person>(predicate: #Predicate { $0.id == id })
                ).first
            else { return nil }
            return .init(title: "Focus person", body: p.displayName)
        default:
            return nil
        }
    }

    private func renderLinkNeighbours(id: UUID, kind: ItemKind, depth: Int) -> AssembledContext.Section? {
        let repo = agentContext.linkRepository
        let outgoing = (try? repo.outgoing(from: (kind, id))) ?? []
        let backlinks = (try? repo.backlinks(to: (kind, id))) ?? []
        let edges = outgoing + backlinks
        guard !edges.isEmpty else { return nil }
        let body = edges.prefix(20).map { "- \($0.linkKind) → \($0.toKind.rawValue):\($0.toID)" }.joined(separator: "\n")
        return .init(title: "Linked items (\(edges.count))", body: body)
    }

    /// Fetches the live-task set (deletedAt == nil) once per assembly, caching it
    /// in `cache` so a second task-backed slice reuses the same array (same query,
    /// same order) instead of re-fetching the whole TaskItem table.
    private func liveTasks(_ cache: inout [TaskItem]?) -> [TaskItem] {
        if let cached = cache { return cached }
        let mc = agentContext.modelContext.context
        // Fetch-then-filter: no force-unwrap inside #Predicate (see Verified contracts).
        let fetched = (try? mc.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        cache = fetched
        return fetched
    }

    private func renderSlice(
        _ slice: RepoSlice, now: Date, liveTasks cache: inout [TaskItem]?
    ) -> AssembledContext.Section? {
        let mc = agentContext.modelContext.context
        switch slice {
        case .tasksDueWithin(let days):
            let end = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
            let all = liveTasks(&cache)
            let tasks = all.filter { if let d = $0.dueAt { return d >= now && d <= end } else { return false } }
            guard !tasks.isEmpty else { return nil }
            return .init(
                title: "Tasks due in \(days)d (\(tasks.count))",
                body: tasks.prefix(30).map { "- \($0.title)" }.joined(separator: "\n"))
        case .overdueTasks:
            let all = liveTasks(&cache)
            let tasks = all.filter { if let d = $0.dueAt { return d < now } else { return false } }
            guard !tasks.isEmpty else { return nil }
            return .init(
                title: "Overdue (\(tasks.count))",
                body: tasks.prefix(30).map { "- \($0.title)" }.joined(separator: "\n"))
        case .projectKeyDates(let projectID):
            let dates = (try? agentContext.projectKeyDateRepository.list(projectID: projectID)) ?? []
            guard !dates.isEmpty else { return nil }
            return .init(
                title: "Key dates (\(dates.count))",
                body: dates.map { "- \($0.label): \($0.date)" }.joined(separator: "\n"))
        case .person(let id):
            guard let p = try? mc.fetch(FetchDescriptor<Person>(predicate: #Predicate { $0.id == id })).first else { return nil }
            return .init(title: "Person", body: "\(p.displayName) \(p.email ?? "")")
        case .recentActivity(let itemID, let kindRaw, let limit):
            guard let kind = ItemKind(rawValue: kindRaw),
                let entries = try? agentContext.activityEntryRepository.entries(for: itemID, kind: kind, limit: limit),
                !entries.isEmpty
            else { return nil }
            // Use eventKindRaw (String) — eventKind is ActivityEventKind? and would print "Optional(...)"
            return .init(
                title: "Recent activity (\(entries.count))",
                body: entries.map { "- \($0.eventKindRaw) @ \($0.createdAt)" }.joined(separator: "\n"))
        }
    }

    // MARK: budget

    private func truncate(_ sections: [AssembledContext.Section], to budget: Int) -> AssembledContext {
        func tokens(_ s: [AssembledContext.Section]) -> Int {
            s.reduce(0) { $0 + TokenBudget.estimate($1.title) + TokenBudget.estimate($1.body) }
        }
        var working = sections
        // 1) trim the RAG section's lines (it is last if present).
        while tokens(working) > budget, let last = working.last, last.title.hasPrefix("Relevant notes") {
            let lines = last.body.split(separator: "\n")
            if lines.count <= 1 { working.removeLast(); break }
            working[working.count - 1] = .init(title: last.title, body: lines.dropLast().joined(separator: "\n"))
        }
        // 2) drop trailing sections until within budget.
        while tokens(working) > budget, !working.isEmpty { working.removeLast() }
        return AssembledContext(sections: working, estimatedTokens: tokens(working))
    }
}
