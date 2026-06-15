import Foundation
import NexusCore
import SwiftData
import Testing

@testable import TasksFeature

@Suite("TasksComposition activity wiring")
@MainActor
struct CompositionActivityWiringTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self, ActivityEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @Test("makeRepository(for:) wires a real ActivityRecorder, not the noop")
    func plainFactoryWiresRecorder() throws {
        let repository = TasksComposition.makeRepository(for: try makeContext())
        #expect(repository.activity is ActivityRecorder)
    }

    @Test("makeRepository(for:notifications:snapshotPusher:) wires a real ActivityRecorder")
    func notificationFactoryWiresRecorder() throws {
        let repository = TasksComposition.makeRepository(
            for: try makeContext(),
            notifications: NoopNotificationScheduler(),
            snapshotPusher: nil
        )
        #expect(repository.activity is ActivityRecorder)
    }
}
