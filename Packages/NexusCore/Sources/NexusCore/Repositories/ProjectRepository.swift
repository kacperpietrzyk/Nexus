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
        parentProjectID: UUID? = nil,
        type: ProjectType = .generic
    ) throws -> Project {
        let stamp = now()
        let project = Project(name: name, color: color, parentProjectID: parentProjectID, type: type)
        project.createdAt = stamp
        project.updatedAt = stamp
        context.insert(project)
        try context.save()
        try applyTypeScaffold(type, to: project.id)
        return project
    }

    /// Seeds the default Sections for a project type (universal-types extension).
    /// Idempotent at call site (only invoked on fresh `create`). `.generic` seeds nothing.
    /// Deliverable-task seeding is deferred to a later tranche.
    public func applyTypeScaffold(_ type: ProjectType, to projectID: UUID) throws {
        let names: [String]
        switch type {
        case .implementation: names = ["Deliverables", "Environment", "Risks"]
        case .sales: names = ["Activities", "Materials"]
        case .audit: names = ["Scope", "Findings", "Report"]
        case .internalDev: names = ["Backlog", "In Progress"]
        case .generic: names = []
        }
        guard !names.isEmpty else { return }
        let sectionRepo = SectionRepository(context: context)
        for name in names {
            _ = try sectionRepo.create(projectID: projectID, name: name)
        }
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

    /// Sets the granular stage, validating it belongs to the project's type preset,
    /// and syncs the coarse `statusRaw` via `ProjectStage.coarseStatus`.
    public func setStage(_ stage: ProjectStage, on project: Project) throws {
        guard project.type.stages.contains(stage) else {
            throw ProjectStageError.stageNotInTypePreset(stage: stage, type: project.type)
        }
        project.stage = stage
        project.statusRaw = stage.coarseStatus.rawValue
        project.updatedAt = now()
        try context.save()
    }

    /// Changes the project type; clears the current stage if it is not in the new
    /// type's preset (keeps `stage ∈ type.stages || stage == nil` invariant).
    public func setType(_ type: ProjectType, on project: Project) throws {
        project.type = type
        if let stage = project.stage, !type.stages.contains(stage) {
            project.stage = nil
        }
        project.updatedAt = now()
        try context.save()
    }

    public func setClient(_ clientID: UUID?, on project: Project) throws {
        project.clientID = clientID
        project.updatedAt = now()
        try context.save()
    }

    public func setVendor(_ vendor: String?, on project: Project) throws {
        project.vendor = vendor
        project.updatedAt = now()
        try context.save()
    }

    /// Sets or removes a single custom field. `value == nil` removes the key.
    public func setCustomField(key: String, value: String?, on project: Project) throws {
        var fields = project.customFields
        if let value {
            fields[key] = value
        } else {
            fields.removeValue(forKey: key)
        }
        project.customFields = fields
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

    public func setPinned(_ project: Project, _ pinned: Bool) throws {
        project.isPinned = pinned
        project.pinnedAt = pinned ? now() : nil
        project.updatedAt = now()
        try context.save()
    }

    public func softDelete(_ project: Project, cascade: Bool = true) throws {
        let stamp = now()
        var visited = Set<UUID>()
        var deletedProjectIDs = Set<UUID>()
        try softDelete(
            project,
            cascade: cascade,
            at: stamp,
            visited: &visited,
            deletedProjectIDs: &deletedProjectIDs
        )
        let commentRepository = CommentRepository(context: context)
        for projectID in deletedProjectIDs {
            try commentRepository.softDeleteAll(for: projectID, kind: .project)
        }
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

    /// Case-insensitive lookup of an active project by NL-capture token
    /// (`@project` in quick add). Two-pass resolution: an exact lowercased-name
    /// match always wins over a space-stripped match (so `@ABC` prefers project
    /// "ABC" over "A BC"); only when no exact candidate exists does the
    /// space-stripped pass run — `@SideProject` and `@sideproject` both match
    /// "Side Project". Within each pass ties break deterministically by name,
    /// then by UUID string, so duplicate-named projects resolve stably across
    /// calls. Archived and deleted projects never match.
    public func findActive(matchingToken token: String) throws -> Project? {
        let needle = token.lowercased()
        guard !needle.isEmpty else { return nil }
        // allActive() sorts by name only; add the UUID-string tie-break for
        // projects sharing a name (no stable secondary order otherwise).
        let candidates = try allActive().sorted {
            ($0.name, $0.id.uuidString) < ($1.name, $1.id.uuidString)
        }
        if let exact = candidates.first(where: { $0.name.lowercased() == needle }) {
            return exact
        }
        return candidates.first { project in
            project.name.lowercased().replacingOccurrences(of: " ", with: "") == needle
        }
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

    private func softDelete(
        _ project: Project,
        cascade: Bool,
        at stamp: Date,
        visited: inout Set<UUID>,
        deletedProjectIDs: inout Set<UUID>
    ) throws {
        guard !visited.contains(project.id) else { return }
        visited.insert(project.id)

        project.deletedAt = stamp
        project.updatedAt = stamp
        deletedProjectIDs.insert(project.id)

        guard cascade else { return }

        let projectID = project.id
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { child in
                child.parentProjectID == projectID && child.deletedAt == nil
            }
        )
        for child in try context.fetch(descriptor) {
            try softDelete(
                child,
                cascade: true,
                at: stamp,
                visited: &visited,
                deletedProjectIDs: &deletedProjectIDs
            )
        }
    }
}

public enum ProjectStageError: Error, Equatable {
    case stageNotInTypePreset(stage: ProjectStage, type: ProjectType)
}
