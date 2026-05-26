import Foundation
import Testing

@testable import NexusAgent

@MainActor
@Test func memoryEditorSectionDefaultsAutoSaveOn() {
    #expect(AgentMemoryEditorSection.defaultAutoSaveEnabled)
}

@MainActor
@Test func memoryEditorViewModelLoadsByScope() throws {
    let ctx = try AgentTestSupport.makeContext()
    let store = AgentMemoryStore(context: ctx)
    _ = try store.upsert(scope: "global", key: "a", content: "1")
    _ = try store.upsert(scope: "project:x", key: "b", content: "2")
    let viewModel = AgentMemoryEditorViewModel(store: store)
    viewModel.scope = "global"
    viewModel.reload()
    #expect(viewModel.entries.count == 1)
    #expect(viewModel.entries.first?.key == "a")
}

@MainActor
@Test func memoryEditorViewModelLoadsProjectAndTagCategoryScopes() throws {
    let ctx = try AgentTestSupport.makeContext()
    let store = AgentMemoryStore(context: ctx)
    _ = try store.upsert(scope: "global", key: "a", content: "1")
    _ = try store.upsert(scope: "project:x", key: "b", content: "2")
    _ = try store.upsert(scope: "tag:y", key: "c", content: "3")
    let viewModel = AgentMemoryEditorViewModel(store: store)

    viewModel.scope = "project"
    viewModel.reload()
    #expect(viewModel.entries.map(\.key) == ["b"])

    viewModel.scope = "tag"
    viewModel.reload()
    #expect(viewModel.entries.map(\.key) == ["c"])
}

@MainActor
@Test func memoryEditorSoftDeletesEntry() throws {
    let ctx = try AgentTestSupport.makeContext()
    let store = AgentMemoryStore(context: ctx)
    let id = try store.upsert(scope: "global", key: "a", content: "1")
    let viewModel = AgentMemoryEditorViewModel(store: store)
    viewModel.scope = "global"
    viewModel.reload()
    viewModel.delete(id: id)
    #expect(viewModel.entries.isEmpty)

    let entry = try #require(try store.find(id: id, includeDeleted: true))
    #expect(entry.deletedAt != nil)
}
