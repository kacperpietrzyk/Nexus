import Foundation
import SwiftData
import Testing

@testable import NexusAgent

@Suite
struct AgentMessageStoreTests {
    @Test func messageStoreSlidingWindow() throws {
        let context = try AgentTestSupport.makeContext()
        let threads = AgentThreadStore(context: context)
        let store = AgentMessageStore(context: context)
        let threadID = try threads.create(title: "t")
        let otherThreadID = try threads.create(title: "other")
        let baseDate = Date(timeIntervalSince1970: 1_800_000_000)

        for i in 0..<15 {
            _ = try store.append(
                threadID: threadID,
                role: .user,
                content: "msg \(i)",
                now: baseDate.addingTimeInterval(TimeInterval(i))
            )
        }
        _ = try store.append(threadID: otherThreadID, role: .user, content: "other")

        let window = try store.slidingWindow(threadID: threadID, last: 10)
        #expect(window.count == 10)
        #expect(window.map(\.content) == (5..<15).map { "msg \($0)" })
    }

    @Test func messageStoreSlidingWindowOrdersTimestampTiesByID() throws {
        let context = try AgentTestSupport.makeContext()
        let store = AgentMessageStore(context: context)
        let threadID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)

        context.insert(AgentThread(id: threadID, title: "t"))
        context.insert(
            AgentMessage(
                id: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
                threadID: threadID,
                createdAt: timestamp,
                role: .user,
                content: "high"
            )
        )
        context.insert(
            AgentMessage(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                threadID: threadID,
                createdAt: timestamp,
                role: .user,
                content: "low"
            )
        )
        context.insert(
            AgentMessage(
                id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
                threadID: threadID,
                createdAt: timestamp,
                role: .user,
                content: "mid"
            )
        )
        try context.save()

        let window = try store.slidingWindow(threadID: threadID, last: 2)
        #expect(window.map(\.content) == ["mid", "high"])
    }

    @Test func messageStoreSlidingWindowRejectsNonPositiveLimits() throws {
        let store = AgentMessageStore(context: try AgentTestSupport.makeContext())
        let threadID = UUID()

        #expect(try store.slidingWindow(threadID: threadID, last: 0).isEmpty)
        #expect(try store.slidingWindow(threadID: threadID, last: -1).isEmpty)
    }
}
