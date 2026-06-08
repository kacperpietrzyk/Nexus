import Foundation
import NexusCore
import Testing

@testable import TasksFeature

struct ProjectEditorSheetTests {
    @Test func existingProjectShowsProjectScopedAccessorySections() {
        let project = Project(name: "Client")

        #expect(
            ProjectEditorAccessorySection.sections(for: project) == [
                .labels(project.id),
                .comments(project.id),
            ])
    }

    @Test func newProjectShowsNoProjectScopedAccessorySections() {
        #expect(ProjectEditorAccessorySection.sections(for: nil).isEmpty)
    }

    @Test func projectCommentsAccessorySuppliesEditorSectionTitle() {
        let projectID = UUID()

        #expect(ProjectEditorAccessorySection.labels(projectID).editorTitle == nil)
        #expect(ProjectEditorAccessorySection.comments(projectID).editorTitle == "Comments")
    }
}
