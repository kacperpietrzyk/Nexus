import Testing

@testable import TasksFeature

@Suite("TasksFeature umbrella")
struct TasksFeatureTests {
    @Test("version is non-empty")
    func versionIsNonEmpty() {
        #expect(!TasksFeature.version.isEmpty)
    }
}
