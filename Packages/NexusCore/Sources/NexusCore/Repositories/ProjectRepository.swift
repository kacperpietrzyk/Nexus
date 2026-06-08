import Foundation
import SwiftData

/// CRUD + archive lifecycle for `Project`. Bound to a single `ModelContext`;
/// never share across actors.
@MainActor
public final class ProjectRepository {
    public let context: ModelContext
    public let now: () -> Date

    public init(context: ModelContext, now: @escaping () -> Date = { .now }) {
        self.context = context
        self.now = now
    }

    @discardableResult
    public func create(
        name: String,
        color: String = "azure",
        parentProjectID: UUID? = nil
    ) throws -> Project {
        let stamp = now()
        let project = Project(name: name, color: color, parentProjectID: parentProjectID)
        project.createdAt = stamp
        project.updatedAt = stamp
        context.insert(project)
        try context.save()
        return project
    }

    public func rename(_ project: Project, to name: String) throws {
        project.name = name
        project.updatedAt = now()
        try context.save()
    }

    public func recolor(_ project: Project, to color: String) throws {
        project.color = color
        project.updatedAt = now()
        try context.save()
    }

    /// Sets the project's lifecycle state (Projects tier, spec §4.1). `ProjectStatus`
    /// has no reconciliation overlay (unlike `WorkflowState ⇒ status` on tasks), so
    /// this is a plain setter; `archivedAt` is orthogonal and left untouched.
    public func setStatus(_ status: ProjectStatus, on project: Project) throws {
        project.statusRaw = status.rawValue
        project.updatedAt = now()
        try context.save()
    }

    public func archive(_ project: Project) throws {
        let stamp = now()
        var visited = Set<UUID>()
        try archive(project, at: stamp, visited: &visited)
        try context.save()
    }

    public func unarchive(_ project: Project) throws {
        project.archivedAt = nil
        project.updatedAt = now()
        try context.save()
    }

    public func allActive() throws -> [Project] {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { project in
                project.deletedAt == nil && project.archivedAt == nil
            },
            sortBy: [SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    public func find(id: UUID) throws -> Project? {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { project in project.id == id }
        )
        return try context.fetch(descriptor).first
    }

    /// Returns the ID set of every non-deleted project whose `archivedAt` is non-nil.
    /// Callers use this to exclude tasks owned by archived projects from active
    /// views (Today/Upcoming/Inbox) without mutating the tasks themselves.
    public func archivedProjectIDs() throws -> Set<UUID> {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { project in
                project.deletedAt == nil && project.archivedAt != nil
            }
        )
        return Set(try context.fetch(descriptor).map(\.id))
    }

    private func archive(_ project: Project, at stamp: Date, visited: inout Set<UUID>) throws {
        guard !visited.contains(project.id) else { return }
        visited.insert(project.id)

        project.archivedAt = stamp
        project.updatedAt = stamp

        let projectID = project.id
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { child in
                child.parentProjectID == projectID && child.deletedAt == nil
            }
        )
        for child in try context.fetch(descriptor) {
            try archive(child, at: stamp, visited: &visited)
        }
    }
}
