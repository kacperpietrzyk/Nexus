import Foundation
import Testing

@testable import NexusCore

@Suite("Project canonicalNoteRef")
struct ProjectNoteRefTests {
    @Test("canonicalNoteRef defaults to nil and is settable")
    func canonicalNoteRefDefaultsAndSettable() {
        let project = Project(name: "Roadmap")
        #expect(project.canonicalNoteRef == nil)
        let ref = UUID()
        project.canonicalNoteRef = ref
        #expect(project.canonicalNoteRef == ref)
    }
}
