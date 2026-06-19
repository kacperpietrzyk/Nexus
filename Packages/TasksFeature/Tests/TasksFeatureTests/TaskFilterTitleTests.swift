import Testing

@testable import TasksFeature

@Suite struct TaskFilterTitleTests {
    @Test func inboxFilterTitleIsUnscheduled() {
        #expect(TaskFilter.inbox.displayTitle == "Unscheduled")
    }
}
