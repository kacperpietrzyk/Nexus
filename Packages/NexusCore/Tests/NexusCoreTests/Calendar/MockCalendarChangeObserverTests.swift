import Foundation
import Testing

@testable import NexusCore

@Suite("MockCalendarChangeObserver")
struct MockCalendarChangeObserverTests {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }

        func increment() {
            lock.lock()
            defer { lock.unlock() }
            count += 1
        }
    }

    @Test("fireChange invokes every registered handler")
    func fireInvokesHandlers() {
        let observer = MockCalendarChangeObserver()
        let counter = Counter()
        observer.observeStoreChanges { counter.increment() }
        observer.observeStoreChanges { counter.increment() }
        observer.fireChange()
        #expect(counter.value == 2)
    }

    @Test("the mock satisfies the CalendarChangeObserving seam")
    func conformance() {
        let observer: any CalendarChangeObserving = MockCalendarChangeObserver()
        observer.observeStoreChanges {}
        // Compiles + returns a token; nothing to assert beyond type-level fit.
        #expect(Bool(true))
    }
}
