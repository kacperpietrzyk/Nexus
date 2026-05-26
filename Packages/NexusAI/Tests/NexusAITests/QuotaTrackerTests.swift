import Testing

@testable import NexusAI

@Test func inMemoryQuotaTracker_default_isUnderLimit() async {
    let q = InMemoryQuotaTracker(dailyTokenLimit: [.whisperKit: 10_000])
    let usage = await q.usage(for: .whisperKit)
    #expect(usage.dailyTokensUsed == 0)
    #expect(usage.dailyTokenLimit == 10_000)
    #expect(usage.isExceeded == false)
}

@Test func inMemoryQuotaTracker_recordUsage_accumulates() async {
    let q = InMemoryQuotaTracker(dailyTokenLimit: [.whisperKit: 100])
    await q.recordUsage(provider: .whisperKit, tokens: 30)
    await q.recordUsage(provider: .whisperKit, tokens: 50)
    let usage = await q.usage(for: .whisperKit)
    #expect(usage.dailyTokensUsed == 80)
    #expect(usage.isExceeded == false)
}

@Test func inMemoryQuotaTracker_atOrAboveLimit_isExceeded() async {
    let q = InMemoryQuotaTracker(dailyTokenLimit: [.whisperKit: 100])
    await q.recordUsage(provider: .whisperKit, tokens: 100)
    let usage = await q.usage(for: .whisperKit)
    #expect(usage.dailyTokensUsed == 100)
    #expect(usage.isExceeded == true)
}

@Test func inMemoryQuotaTracker_unlimitedProvider_isNeverExceeded() async {
    let q = InMemoryQuotaTracker(dailyTokenLimit: [:])  // no entry => unlimited
    await q.recordUsage(provider: .appleIntelligence, tokens: 1_000_000)
    let usage = await q.usage(for: .appleIntelligence)
    #expect(usage.isExceeded == false)
    #expect(usage.dailyTokenLimit == nil)
}
