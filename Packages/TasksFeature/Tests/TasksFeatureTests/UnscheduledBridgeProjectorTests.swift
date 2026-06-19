// Packages/TasksFeature/Tests/TasksFeatureTests/UnscheduledBridgeProjectorTests.swift
import Foundation
import Testing
import InboxShell
@testable import TasksFeature

@MainActor
@Suite struct UnscheduledBridgeProjectorTests {
    @Test func emitsSingleBridgeWhenCountPositive() async throws {
        let projector = UnscheduledBridgeProjector(countProvider: { 1382 })
        let items = try await projector.project()
        #expect(items.count == 1)
        #expect(items.first?.key == "bridge:unscheduled")
        #expect(items.first?.stream == .bridge)
        #expect(items.first?.title.contains("1382") == true)
        #expect(items.first?.route == .unscheduledTasks)
    }

    @Test func emitsNothingWhenZero() async throws {
        let projector = UnscheduledBridgeProjector(countProvider: { 0 })
        #expect(try await projector.project().isEmpty)
    }
}
