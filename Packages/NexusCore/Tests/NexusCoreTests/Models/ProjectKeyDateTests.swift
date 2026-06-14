import Foundation
import SwiftData
import Testing
@testable import NexusCore

@Suite("ProjectKeyDate")
struct ProjectKeyDateTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([ProjectKeyDate.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    @MainActor
    @Test("key date persists and round-trips, scoped by projectID")
    func roundTrip() throws {
        let context = try makeContext()
        let projectID = UUID()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let keyDate = ProjectKeyDate(projectID: projectID, anchorKey: "T0", label: "Podpisanie umowy", date: t0, isContractual: true)
        context.insert(keyDate)
        try context.save()

        let fetched = try context.fetch(
            FetchDescriptor<ProjectKeyDate>(predicate: #Predicate { $0.projectID == projectID })
        )
        #expect(fetched.count == 1)
        #expect(fetched.first?.anchorKey == "T0")
        #expect(fetched.first?.isContractual == true)
        #expect(fetched.first?.date == t0)
    }
}
