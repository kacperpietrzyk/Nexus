import Foundation
import Testing

@testable import NexusCore
@testable import TasksFeature

@Suite("Save current filter mapping")
struct SaveCurrentFilterSheetTests {
    @Test("maps faithful sidebar task filters to saved filter definitions")
    func mapsSupportedTaskFiltersToFilterDefinitions() {
        let projectID = UUID()
        let sectionID = UUID()

        #expect(SaveCurrentFilterDescriptor.make(for: .byTag("work"))?.definition == .byTag("work"))
        #expect(SaveCurrentFilterDescriptor.make(for: .project(projectID))?.definition == .byProject(projectID))
        #expect(
            SaveCurrentFilterDescriptor.make(for: .projectSection(projectID, sectionID))?.definition
                == .bySection(sectionID)
        )
    }

    @Test("rejects filters that cannot be represented by FilterDefinition")
    func rejectsUnsupportedFilters() {
        #expect(SaveCurrentFilterDescriptor.make(for: .all) == nil)
        #expect(SaveCurrentFilterDescriptor.make(for: .today) == nil)
        #expect(SaveCurrentFilterDescriptor.make(for: .upcoming) == nil)
        #expect(SaveCurrentFilterDescriptor.make(for: .inbox) == nil)
        #expect(SaveCurrentFilterDescriptor.make(for: .completed) == nil)
        #expect(SaveCurrentFilterDescriptor.make(for: .savedFilter(UUID())) == nil)
    }

    @Test("explains unsupported built-in filters")
    func explainsUnsupportedBuiltInFilters() {
        #expect(SaveCurrentFilterUnsupportedReason.message(for: .today).contains("cannot be saved yet"))
        #expect(SaveCurrentFilterUnsupportedReason.message(for: .upcoming).contains("cannot be saved yet"))
        #expect(SaveCurrentFilterUnsupportedReason.message(for: .inbox).contains("future snoozed tasks"))
        #expect(
            SaveCurrentFilterUnsupportedReason.message(for: .savedFilter(UUID()))
                .contains("cannot be saved as another Smart List")
        )
    }
}
