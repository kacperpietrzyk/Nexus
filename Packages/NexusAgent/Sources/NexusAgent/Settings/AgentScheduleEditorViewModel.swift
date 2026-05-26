import Combine
import Foundation

@MainActor
public final class AgentScheduleEditorViewModel: ObservableObject {
    @Published public private(set) var schedules: [AgentSchedule] = []

    private let store: any AgentScheduleStoreProviding

    public init(store: any AgentScheduleStoreProviding) {
        self.store = store
        reload()
    }

    public func reload() {
        schedules = (try? store.allActive()) ?? []
    }

    @discardableResult
    public func save(
        id: UUID? = nil,
        name: String,
        cronExpression: String,
        prompt: String,
        enabled: Bool,
        threadID: UUID? = nil,
        modelHint: String? = nil
    ) throws -> UUID {
        _ = try CronExpression(cronExpression)
        let id = try store.save(
            AgentScheduleStoreMutation(
                name: name,
                cronExpression: cronExpression,
                prompt: prompt,
                threadID: threadID,
                modelHint: nil,
                enabled: enabled
            ),
            id: id
        )
        reload()
        return id
    }

    public func setEnabled(_ enabled: Bool, id: UUID) throws {
        try store.setEnabled(enabled, id: id)
        reload()
    }
}
