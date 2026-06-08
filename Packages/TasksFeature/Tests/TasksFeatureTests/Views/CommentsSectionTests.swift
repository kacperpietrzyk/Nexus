import Foundation
import NexusCore
import Testing
@testable import TasksFeature

@Suite struct CommentsSectionTests {
    @Test func trimsBlankBeforeAdd() {
        #expect(CommentsComposer.sanitized("  hi  ") == "hi")
        #expect(CommentsComposer.sanitized("   ") == nil)
    }

    @Test func failedAddKeepsDraftAndSurfacesError() {
        let result = CommentsComposer.addResult(draft: "  still here  ") { _ in
            throw CommentSaveFailure()
        }

        #expect(result.draft == "  still here  ")
        #expect(result.errorMessage == "Could not add comment.")
        #expect(result.shouldReload == false)
    }

    @Test func failedReloadKeepsExistingCommentsAndSurfacesError() {
        let existing = [
            Comment(itemID: UUID(), itemKind: .task, body: "imported Todoist comment")
        ]

        let result = CommentsLoader.reloadResult(existing: existing) {
            throw CommentLoadFailure()
        }

        #expect(result.comments.map(\.body) == ["imported Todoist comment"])
        #expect(result.errorMessage == "Could not load comments.")
    }
}

private struct CommentSaveFailure: Error {}
private struct CommentLoadFailure: Error {}
