import Testing
@testable import NexusCore

@Suite("ProjectType")
struct ProjectTypeTests {
    @Test("raw values are stable and cover all five types")
    func rawValues() {
        #expect(ProjectType.implementation.rawValue == "implementation")
        #expect(ProjectType.sales.rawValue == "sales")
        #expect(ProjectType.audit.rawValue == "audit")
        #expect(ProjectType.internalDev.rawValue == "internalDev")
        #expect(ProjectType.generic.rawValue == "generic")
        #expect(ProjectType.allCases.count == 5)
    }

    @Test("unknown raw decodes to nil (caller falls back to .generic)")
    func unknownRaw() {
        #expect(ProjectType(rawValue: "nope") == nil)
    }

    @Test("display names are human-facing")
    func displayNames() {
        #expect(ProjectType.implementation.displayName == "Implementation")
        #expect(ProjectType.internalDev.displayName == "Internal / Dev")
        #expect(ProjectType.generic.displayName == "Project")
    }
}
