import Foundation
import Testing

@testable import NotesFeature

@MainActor
@Suite("GraphOpenRequest - cross-layer open handoff")
struct GraphOpenRequestTests {
    private final class Counter: @unchecked Sendable {
        var value = 0
    }

    @Test("request marks pending and posts the notification")
    func requestPostsAndMarks() {
        let center = NotificationCenter()
        let request = GraphOpenRequest()
        let received = Counter()
        let token = center.addObserver(
            forName: .notesOpenGraph, object: nil, queue: nil
        ) { _ in received.value += 1 }
        defer { center.removeObserver(token) }

        request.request(center: center)

        #expect(request.isPending)
        #expect(received.value == 1)
    }

    @Test("consume returns true exactly once per request")
    func consumeIsOneShot() {
        let request = GraphOpenRequest()
        #expect(!request.consume())

        request.request(center: NotificationCenter())
        #expect(request.consume())
        #expect(!request.consume())
    }
}
