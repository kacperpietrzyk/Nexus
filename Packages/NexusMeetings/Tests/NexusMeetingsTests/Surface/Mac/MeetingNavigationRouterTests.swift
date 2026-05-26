import Foundation
import Testing
@testable import NexusMeetings

@MainActor
@Test func routerEmitsMeetingIDOnNavigate() async {
    let router = MeetingNavigationRouter()
    let target = UUID()

    router.navigate(to: target)

    var iterator = router.selections.makeAsyncIterator()
    let seen = await iterator.next()

    #expect(seen == target)
}
