import Foundation
import Testing

@testable import NotesFeature

@MainActor
struct DailyNoteOpenRequestTests {
    /// `@unchecked Sendable` mutable box; the notification is posted (and the
    /// observer run) synchronously on the test's actor.
    private final class Counter: @unchecked Sendable {
        var value = 0
    }

    @Test func requestSetsPendingAndPostsNotification() {
        let request = DailyNoteOpenRequest()
        let center = NotificationCenter()
        let received = Counter()
        let token = center.addObserver(
            forName: .notesOpenDailyNote, object: nil, queue: nil
        ) { _ in received.value += 1 }
        defer { center.removeObserver(token) }

        request.request(center: center)

        #expect(received.value == 1)
        #expect(request.isPending)
    }

    @Test func consumeReturnsTrueOnceThenFalse() {
        let request = DailyNoteOpenRequest()
        request.request(center: NotificationCenter())

        #expect(request.consume())
        #expect(!request.consume())
    }

    @Test func consumeWithoutRequestIsFalse() {
        #expect(!DailyNoteOpenRequest().consume())
    }
}
