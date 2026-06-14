import Foundation
import Testing
@testable import NexusAgent

@Suite struct InsightCooldownStoreTests {
    private func freshStore(now: @escaping () -> Date) -> InsightCooldownStore {
        let suite = UUID().uuidString
        let ud = UserDefaults(suiteName: suite)!
        ud.removePersistentDomain(forName: suite)
        return InsightCooldownStore(defaults: ud, now: now)
    }

    @Test func firesFirstTimeThenSuppressedWithinCooldown() {
        var t = Date(timeIntervalSince1970: 1_800_000_000)
        let s = freshStore(now: { t })
        #expect(s.shouldFire(key: "overload:2026-06-15", cooldown: 3600) == true)
        s.record(key: "overload:2026-06-15")
        t = t.addingTimeInterval(1800)  // 30 min later
        #expect(s.shouldFire(key: "overload:2026-06-15", cooldown: 3600) == false)
        t = t.addingTimeInterval(2000)  // > 1h total
        #expect(s.shouldFire(key: "overload:2026-06-15", cooldown: 3600) == true)
    }

    @Test func differentKeysAreIndependent() {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let s = freshStore(now: { t })
        s.record(key: "a")
        #expect(s.shouldFire(key: "b", cooldown: 3600) == true)
    }
}
