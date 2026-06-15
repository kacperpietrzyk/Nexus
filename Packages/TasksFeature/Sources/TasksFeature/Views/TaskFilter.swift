import Foundation

/// Selection state for the sidebar / iOS tabs. Drives `TaskListView`
/// section layout and which `TaskBucket` it fetches.
public enum TaskFilter: Hashable, Sendable {
    case all
    case today
    case upcoming
    case inbox
    case completed
    case templates
    case byTag(String)
    case project(UUID)
    case projectSection(UUID, UUID)
    case savedFilter(UUID)
    case cycle(UUID)
}

extension TaskFilter {
    public var displayTitle: String {
        resolvedDisplayTitle()
    }

    public func resolvedDisplayTitle(
        projectName: (UUID) -> String? = { _ in nil },
        sectionName: (UUID, UUID) -> String? = { _, _ in nil },
        savedFilterName: (UUID) -> String? = { _ in nil },
        cycleName: (UUID) -> String? = { _ in nil }
    ) -> String {
        switch self {
        case .all:
            return "All Tasks"
        case .today:
            return "Today"
        case .upcoming:
            return "Upcoming"
        case .inbox:
            return "Inbox"
        case .completed:
            return "Done"
        case .templates:
            return "Templates"
        case .byTag(let tag):
            return "#\(tag)"
        case .project(let projectID):
            return projectName(projectID) ?? "Project"
        case .projectSection(let projectID, let sectionID):
            return sectionName(projectID, sectionID) ?? projectName(projectID) ?? "Section"
        case .savedFilter(let filterID):
            return savedFilterName(filterID) ?? "Saved Filter"
        case .cycle(let cycleID):
            return cycleName(cycleID) ?? "Cycle"
        }
    }

    public func replacingArchivedProject(_ projectID: UUID, fallback: TaskFilter = .upcoming) -> TaskFilter {
        switch self {
        case .project(let selectedProjectID) where selectedProjectID == projectID:
            return fallback
        case .projectSection(let selectedProjectID, _) where selectedProjectID == projectID:
            return fallback
        default:
            return self
        }
    }
}
