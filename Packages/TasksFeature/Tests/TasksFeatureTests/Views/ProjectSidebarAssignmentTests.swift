import Foundation
import SwiftData
import Testing

@testable import NexusCore
@testable import TasksFeature

@Suite("ProjectSidebarAssignment")
struct ProjectSidebarAssignmentTests {
    @MainActor
    @Test("Drop assignment routes through repository validation")
    func dropAssignmentRoutesThroughRepositoryValidation() throws {
        let schema = Schema([TaskItem.self, Project.self, Section.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let repository = TaskItemRepository(
            context: context,
            scheduler: RRuleScheduler(),
            now: { Date(timeIntervalSinceReferenceDate: 900_000) }
        )

        let projectID = UUID()
        let otherProjectID = UUID()
        let targetProject = Project(id: projectID, name: "Target")
        let otherProject = Project(id: otherProjectID, name: "Other")
        let otherProjectSection = Section(projectID: otherProjectID, name: "Elsewhere")
        let task = TaskItem(title: "Move me")
        context.insert(targetProject)
        context.insert(otherProject)
        context.insert(otherProjectSection)
        try repository.insert(task)

        #expect(
            throws: ProjectSectionAssignmentError.sectionProjectMismatch(
                sectionID: otherProjectSection.id,
                expectedProjectID: projectID,
                actualProjectID: otherProjectID
            )
        ) {
            try ProjectSidebarAssignment.assign(
                payloads: [TaskItemDropPayload(taskID: task.id)],
                projectID: projectID,
                sectionID: otherProjectSection.id,
                modelContext: context,
                repository: repository
            )
        }
        #expect(task.projectID == nil)
        #expect(task.sectionID == nil)
    }

    @MainActor
    @Test("Drop assignment stores only task-id payloads on successful project drop")
    func dropAssignmentStoresTaskIDPayloadsOnSuccess() throws {
        let schema = Schema([TaskItem.self, Project.self, Section.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let repository = TaskItemRepository(
            context: context,
            scheduler: RRuleScheduler(),
            now: { Date(timeIntervalSinceReferenceDate: 900_000) }
        )

        let projectID = UUID()
        let project = Project(id: projectID, name: "Target")
        let task = TaskItem(title: "Move me")
        context.insert(project)
        try repository.insert(task)

        let assigned = try ProjectSidebarAssignment.assign(
            payloads: [TaskItemDropPayload(taskID: task.id)],
            projectID: projectID,
            sectionID: nil,
            modelContext: context,
            repository: repository
        )

        #expect(assigned)
        #expect(task.projectID == projectID)
        #expect(task.sectionID == nil)
    }
}
