import Foundation

public struct IdempotentResponseDTO: Codable, Sendable, Equatable {
    public let task: TaskDTO
    public let wasCreated: Bool

    private enum CodingKeys: String, CodingKey {
        case task
        case wasCreated = "was_created"
    }

    public init(task: TaskDTO, wasCreated: Bool) {
        self.task = task
        self.wasCreated = wasCreated
    }
}
