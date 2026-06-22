import Testing

@testable import NexusAgentTools

@Suite("CoreTaskTools registry")
struct CoreTaskToolsRegistryTests {
    @Test("registry exposes all new MCP gap tools")
    func registersNewTools() {
        let names = Set(CoreTaskTools.all().map(\.name))
        let expected: Set<String> = [
            "note.delete", "search.global",
            "projects.list", "projects.update", "projects.archive", "projects.unarchive",
            "projects.delete",
            "projects.sections.list", "projects.sections.update", "projects.sections.delete",
            "projects.sections.reorder",
            "labels.create", "labels.update", "labels.delete",
            "cycles.create", "cycles.update", "cycles.set_status", "cycles.delete",
            "saved_filters.list", "saved_filters.create", "saved_filters.update",
            "saved_filters.delete", "saved_filters.apply",
            "tasks.set_reminders",
            "calendar.preferences.get", "calendar.preferences.update",
            "stats.goals.get", "stats.goals.update", "stats.productivity",
            "export.item", "export.bundle",
            "projects.overview",
            "links.reclassify_project_membership",
        ]
        #expect(expected.isSubset(of: names))
    }

    @Test("tool names are unique")
    func uniqueNames() {
        let all = CoreTaskTools.all().map(\.name)
        #expect(all.count == Set(all).count)
    }
}
