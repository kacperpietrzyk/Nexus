import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("QuotaLog")
struct QuotaLogTests {

    @Test("init sets all fields")
    func initFields() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_777_887_600)
        let log = QuotaLog(
            id: id,
            providerRaw: "chatGPTOAuth",
            day: date,
            promptTokens: 1234,
            completionTokens: 567
        )
        #expect(log.id == id)
        #expect(log.providerRaw == "chatGPTOAuth")
        #expect(log.day == date)
        #expect(log.promptTokens == 1234)
        #expect(log.completionTokens == 567)
    }

    @Test("totalTokens sums prompt + completion")
    func totalTokens() {
        let log = QuotaLog(
            id: UUID(),
            providerRaw: "appleIntelligence",
            day: .now,
            promptTokens: 100,
            completionTokens: 200
        )
        #expect(log.totalTokens == 300)
    }

    @Test("inserts into in-memory ModelContainer")
    func insertable() throws {
        let schema = Schema([QuotaLog.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)
        let log = QuotaLog(
            id: UUID(),
            providerRaw: "chatGPTOAuth",
            day: .now,
            promptTokens: 10,
            completionTokens: 20
        )
        context.insert(log)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<QuotaLog>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.providerRaw == "chatGPTOAuth")
    }
}
