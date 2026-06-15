import Foundation
import Testing

@testable import NexusCore

@Suite struct CommentTests {
    @Test func initSetsDefaultsAndAnchor() {
        let itemID = UUID()
        let comment = Comment(itemID: itemID, itemKind: .task, body: "first note")

        #expect(comment.itemID == itemID)
        #expect(comment.itemKind == .task)
        #expect(comment.body == "first note")
        #expect(comment.deletedAt == nil)
        #expect(comment.externalSourceID == nil)
        #expect(comment.createdAt == comment.updatedAt)
    }

    @Test func anchorsToProject() {
        let comment = Comment(itemID: UUID(), itemKind: .project, body: "project note")
        #expect(comment.itemKind == .project)
    }
}
