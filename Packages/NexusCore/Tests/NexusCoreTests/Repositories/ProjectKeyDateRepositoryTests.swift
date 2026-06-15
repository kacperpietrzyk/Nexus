import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("ProjectKeyDateRepository")
struct ProjectKeyDateRepositoryTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([ProjectKeyDate.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    @MainActor
    @Test("setKeyDate upserts by (projectID, anchorKey); list is date-sorted")
    func upsertAndList() throws {
        let context = try makeContext()
        let repo = ProjectKeyDateRepository(context: context)
        let projectID = UUID()
        let early = Date(timeIntervalSince1970: 1_800_000_000)
        let later = Date(timeIntervalSince1970: 1_810_000_000)

        try repo.setKeyDate(projectID: projectID, anchorKey: "PO", label: "Protokół Odbioru", date: later, isContractual: true)
        try repo.setKeyDate(projectID: projectID, anchorKey: "T0", label: "Podpisanie umowy", date: early, isContractual: true)
        try repo.setKeyDate(projectID: projectID, anchorKey: "T0", label: "Umowa", date: early, isContractual: true)

        let list = try repo.list(projectID: projectID)
        #expect(list.map(\.anchorKey) == ["T0", "PO"])
        #expect(list.first?.label == "Umowa")
    }

    @MainActor
    @Test("delete removes a key date")
    func delete() throws {
        let context = try makeContext()
        let repo = ProjectKeyDateRepository(context: context)
        let projectID = UUID()
        try repo.setKeyDate(projectID: projectID, anchorKey: "T0", label: "x", date: .now)

        try repo.delete(projectID: projectID, anchorKey: "T0")
        #expect(try repo.list(projectID: projectID).isEmpty)
    }
}
