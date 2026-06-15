import Foundation
import NexusCore
import SwiftData
import Testing

@testable import TasksFeature

@Suite("TaskFilter.templates")
struct TemplatesFilterTests {
    @Test("displayTitle")
    func displayTitle() {
        #expect(TaskFilter.templates.displayTitle == "Templates")
    }

    @Test("replacingArchivedProject leaves .templates untouched")
    func archivedProjectFallback() {
        #expect(TaskFilter.templates.replacingArchivedProject(UUID()) == .templates)
    }

    @Test("empty state for .templates")
    func emptyState() {
        let state = TaskListEmptyState.resolve(filter: .templates, isEmpty: true, hasError: false)
        guard case .empty(let title, _, _) = state else {
            Issue.record("expected .empty, got \(state)")
            return
        }
        #expect(title == "No templates")
    }

    @MainActor
    @Test("templateTasks lists root templates only")
    func templateTasksStatic() throws {
        let schema = Schema([TaskItem.self, Project.self, Note.self, Link.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let root = TaskItem(title: "tpl root", isTemplate: true)
        context.insert(root)
        context.insert(TaskItem(title: "tpl child", parentTaskID: root.id, isTemplate: true))
        context.insert(TaskItem(title: "live"))
        try context.save()

        let templates = try TaskListView.templateTasks(modelContext: context)
        #expect(templates.map(\.title) == ["tpl root"])
    }
}
