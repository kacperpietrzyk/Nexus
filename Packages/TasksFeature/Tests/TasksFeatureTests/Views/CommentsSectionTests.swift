import Foundation
import NexusCore
import Testing
@testable import TasksFeature

@Suite struct CommentsSectionTests {
    @Test func trimsBlankBeforeAdd() {
        #expect(CommentsComposer.sanitized("  hi  ") == "hi")
        #expect(CommentsComposer.sanitized("   ") == nil)
    }
}
