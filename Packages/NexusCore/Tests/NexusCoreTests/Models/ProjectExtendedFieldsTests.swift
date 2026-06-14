import Foundation
import SwiftData
import Testing
@testable import NexusCore

@Suite("Project extended fields")
struct ProjectExtendedFieldsTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Project.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    @MainActor
    @Test("new project defaults to generic type, nil stage, empty custom fields")
    func defaults() throws {
        let context = try makeContext()
        let project = Project(name: "Blank")
        context.insert(project)
        try context.save()

        #expect(project.type == .generic)
        #expect(project.stage == nil)
        #expect(project.clientID == nil)
        #expect(project.vendor == nil)
        #expect(project.customFields.isEmpty)
    }

    @MainActor
    @Test("type/stage/customFields accessors round-trip through raw storage")
    func accessorsRoundTrip() throws {
        let context = try makeContext()
        let project = Project(name: "AKMF", type: .implementation)
        project.stage = .deliveryDocs
        project.clientID = UUID()
        project.vendor = "Proofpoint DLP"
        project.customFields = ["dealValue": "690891 PLN", "competitor": "Apius"]
        context.insert(project)
        try context.save()

        let id = project.id
        let fetched = try context.fetch(
            FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })
        ).first
        #expect(fetched?.type == .implementation)
        #expect(fetched?.typeRaw == "implementation")
        #expect(fetched?.stage == .deliveryDocs)
        #expect(fetched?.vendor == "Proofpoint DLP")
        #expect(fetched?.customFields["dealValue"] == "690891 PLN")
        #expect(fetched?.customFields["competitor"] == "Apius")
    }

    @MainActor
    @Test("unknown stored type raw falls back to generic")
    func unknownTypeRaw() throws {
        let project = Project(name: "X")
        project.typeRaw = "bogus"
        #expect(project.type == .generic)
    }
}
