import Foundation
import Testing

@testable import NexusAgent

@MainActor
@Test func editorViewModelCreatesSchedule() throws {
    let ctx = try AgentTestSupport.makeContext()
    let store = AgentScheduleStore(context: ctx)
    let viewModel = AgentScheduleEditorViewModel(store: store)
    let id = try viewModel.save(
        name: "Custom 1",
        cronExpression: "*/30 * * * *",
        prompt: "ping",
        enabled: true
    )
    let fetched = try store.get(id: id)
    #expect(fetched?.name == "Custom 1")
    #expect(fetched?.enabled == true)
}

@MainActor
@Test func editorViewModelRejectsBadCron() throws {
    let ctx = try AgentTestSupport.makeContext()
    let store = AgentScheduleStore(context: ctx)
    let viewModel = AgentScheduleEditorViewModel(store: store)
    #expect(throws: CronExpressionError.self) {
        _ = try viewModel.save(name: "bad", cronExpression: "garbage", prompt: "x", enabled: true)
    }
}

@MainActor
@Test func editorViewModelUpdatesExistingScheduleWithoutChangingKind() throws {
    let ctx = try AgentTestSupport.makeContext()
    let store = AgentScheduleStore(context: ctx)
    let threadID = try AgentThreadStore(context: ctx).create(title: "Pinned")
    let id = try store.create(
        name: "Digest",
        kind: .projectDigest,
        cronExpression: "0 8 * * *",
        prompt: "old prompt"
    )

    let viewModel = AgentScheduleEditorViewModel(store: store)
    let savedID = try viewModel.save(
        id: id,
        name: "Updated digest",
        cronExpression: "*/30 * * * *",
        prompt: "new prompt",
        enabled: false,
        threadID: threadID,
        modelHint: "claude"
    )

    let fetched = try #require(try store.get(id: id))
    #expect(savedID == id)
    #expect(fetched.name == "Updated digest")
    #expect(fetched.kind == .projectDigest)
    #expect(fetched.cronExpression == "*/30 * * * *")
    #expect(fetched.prompt == "new prompt")
    #expect(fetched.enabled == false)
    #expect(fetched.threadID == threadID)
    #expect(fetched.modelHint == nil)
}

@MainActor
@Test func editorViewModelRejectsBadCronBeforeUpdatingExistingSchedule() throws {
    let ctx = try AgentTestSupport.makeContext()
    let store = AgentScheduleStore(context: ctx)
    let id = try store.create(
        name: "Digest",
        kind: .builtIn,
        cronExpression: "0 8 * * *",
        prompt: "old prompt"
    )

    let viewModel = AgentScheduleEditorViewModel(store: store)
    #expect(throws: CronExpressionError.self) {
        _ = try viewModel.save(
            id: id,
            name: "Bad update",
            cronExpression: "garbage",
            prompt: "new prompt",
            enabled: false
        )
    }

    let fetched = try #require(try store.get(id: id))
    #expect(fetched.name == "Digest")
    #expect(fetched.kind == .builtIn)
    #expect(fetched.cronExpression == "0 8 * * *")
    #expect(fetched.prompt == "old prompt")
    #expect(fetched.enabled == true)
}

@MainActor
@Test func editorViewModelUpdatesExistingScheduleWithoutClearingProjectID() throws {
    let ctx = try AgentTestSupport.makeContext()
    let store = AgentScheduleStore(context: ctx)
    let projectID = UUID()
    let id = try store.create(
        name: "Project digest",
        kind: .projectDigest,
        cronExpression: "0 8 * * *",
        prompt: "old prompt",
        projectID: projectID
    )

    let viewModel = AgentScheduleEditorViewModel(store: store)
    try viewModel.save(
        id: id,
        name: "Updated project digest",
        cronExpression: "0 9 * * *",
        prompt: "new prompt",
        enabled: false,
        modelHint: "local"
    )

    let fetched = try #require(try store.get(id: id))
    #expect(fetched.kind == .projectDigest)
    #expect(fetched.projectID == projectID)
    #expect(fetched.name == "Updated project digest")
    #expect(fetched.cronExpression == "0 9 * * *")
    #expect(fetched.prompt == "new prompt")
    #expect(fetched.enabled == false)
    #expect(fetched.modelHint == nil)
}

@MainActor
@Test func editorViewModelTogglesEnabled() throws {
    let ctx = try AgentTestSupport.makeContext()
    let store = AgentScheduleStore(context: ctx)
    let id = try store.create(name: "x", cronExpression: "0 8 * * *", prompt: "x")
    let viewModel = AgentScheduleEditorViewModel(store: store)
    try viewModel.setEnabled(false, id: id)
    #expect(try store.get(id: id)?.enabled == false)
}

@Test func scheduleModelHintDisplayNormalizesLegacyCloudHints() {
    #expect(AgentScheduleModelHintDisplay.badgeTitle(for: "openai") == "Auto")
    #expect(AgentScheduleModelHintDisplay.badgeTitle(for: "byok") == "Auto")
    #expect(AgentScheduleModelHintDisplay.badgeTitle(for: "claude") == "Auto")
    #expect(AgentScheduleModelHintDisplay.badgeTitle(for: "custom") == nil)
    #expect(AgentScheduleModelHintDisplay.editableValue(for: "claude") == nil)
}
