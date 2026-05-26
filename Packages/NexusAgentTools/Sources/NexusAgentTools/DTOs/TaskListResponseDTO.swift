import Foundation

public struct TaskListResponseDTO: Codable, Sendable, Equatable {
    public let tasks: [TaskDTO]
    public let total: Int
    public let hasMore: Bool

    private enum CodingKeys: String, CodingKey {
        case tasks, total
        case hasMore = "has_more"
    }

    public init(tasks: [TaskDTO], total: Int, hasMore: Bool) {
        self.tasks = tasks
        self.total = total
        self.hasMore = hasMore
    }
}
