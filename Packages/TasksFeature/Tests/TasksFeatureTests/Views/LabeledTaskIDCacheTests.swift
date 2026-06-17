import Foundation
import Testing

@testable import TasksFeature

/// FIX 3a: the labeled-task-id cache re-runs the fetch ONLY when `labelID`
/// changes, and returns the identical id-set the fetch produced. Pixel-identical:
/// the filter sees the same ids whether resolved fresh or from cache.
@Suite("Labeled task id cache")
struct LabeledTaskIDCacheTests {

    @Test("re-fetches only when labelID changes; returns identical ids")
    func memoizesByLabelID() {
        var cache = LabeledTaskIDCache()
        var fetchCount = 0
        let a = UUID()
        let b = UUID()
        let idsForA: Set<UUID> = [UUID(), UUID()]
        let idsForB: Set<UUID> = [UUID()]

        func fetch(_ labelID: UUID?) -> Set<UUID>? {
            fetchCount += 1
            switch labelID {
            case a: return idsForA
            case b: return idsForB
            default: return nil
            }
        }

        // First resolve for A -> one fetch.
        #expect(cache.ids(for: a, fetch: fetch) == idsForA)
        #expect(fetchCount == 1)

        // Same label again -> NO new fetch, identical ids.
        #expect(cache.ids(for: a, fetch: fetch) == idsForA)
        #expect(fetchCount == 1)

        // Different label -> exactly one new fetch.
        #expect(cache.ids(for: b, fetch: fetch) == idsForB)
        #expect(fetchCount == 2)

        // Back to A -> labelID differs from last (B) -> re-fetch (no LRU), same ids.
        #expect(cache.ids(for: a, fetch: fetch) == idsForA)
        #expect(fetchCount == 3)
    }

    @Test("invalidate forces a re-fetch even when labelID is unchanged")
    func invalidateForcesRefetch() {
        var cache = LabeledTaskIDCache()
        var fetchCount = 0
        let a = UUID()
        // The label→task graph can change (store-change) WITHOUT labelID changing;
        // invalidate() must drop the cache so the next resolve reflects it.
        var current: Set<UUID> = [UUID()]
        func fetch(_ labelID: UUID?) -> Set<UUID>? {
            fetchCount += 1
            return current
        }

        let first = cache.ids(for: a, fetch: fetch)
        #expect(first == current)
        #expect(fetchCount == 1)

        // Graph changes under the same label; without invalidate the cache is stale.
        current = [UUID(), UUID()]
        cache.invalidate()
        let second = cache.ids(for: a, fetch: fetch)
        #expect(second == current)
        #expect(fetchCount == 2)
    }

    @Test("caches a nil labelID resolution without re-fetching")
    func memoizesNilLabel() {
        var cache = LabeledTaskIDCache()
        var fetchCount = 0
        func fetch(_ labelID: UUID?) -> Set<UUID>? {
            fetchCount += 1
            return nil
        }

        #expect(cache.ids(for: nil, fetch: fetch) == nil)
        #expect(fetchCount == 1)
        // Repeated nil -> cached, no second fetch.
        #expect(cache.ids(for: nil, fetch: fetch) == nil)
        #expect(fetchCount == 1)
    }
}
