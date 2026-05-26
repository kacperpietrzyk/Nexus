import Foundation
import SwiftData
import Testing

@testable import NexusCore

@MainActor
@Test func linkableRepository_insertAndFetchByID() throws {
    let context = try makeContext()
    let repo = LinkableRepository<DebugItem>(context: context)
    let item = DebugItem(title: "Insert me")
    try repo.insert(item)

    let found = try repo.find(id: item.id)
    #expect(found?.title == "Insert me")
}

@MainActor
@Test func linkableRepository_fetchAll_excludesSoftDeleted() throws {
    let context = try makeContext()
    let repo = LinkableRepository<DebugItem>(context: context)

    let alive = DebugItem(title: "alive")
    let dead = DebugItem(title: "dead")
    try repo.insert(alive)
    try repo.insert(dead)

    try repo.softDelete(dead)

    let live = try repo.fetchAll()
    #expect(live.count == 1)
    #expect(live.first?.title == "alive")
}

@MainActor
@Test func linkableRepository_fetchAllIncludingDeleted_returnsBoth() throws {
    let context = try makeContext()
    let repo = LinkableRepository<DebugItem>(context: context)

    let alive = DebugItem(title: "alive")
    let dead = DebugItem(title: "dead")
    try repo.insert(alive)
    try repo.insert(dead)
    try repo.softDelete(dead)

    let all = try repo.fetchAllIncludingDeleted()
    #expect(all.count == 2)
}

@MainActor
@Test func linkableRepository_softDelete_setsDeletedAtAndUpdatedAt() throws {
    let context = try makeContext()
    let repo = LinkableRepository<DebugItem>(context: context)
    let item = DebugItem(title: "x")
    try repo.insert(item)
    let before = item.updatedAt

    try repo.softDelete(item)

    #expect(item.deletedAt != nil)
    #expect(item.updatedAt > before)
}

@MainActor
@Test func linkableRepository_restore_clearsDeletedAt() throws {
    let context = try makeContext()
    let repo = LinkableRepository<DebugItem>(context: context)
    let item = DebugItem(title: "x")
    try repo.insert(item)
    try repo.softDelete(item)
    #expect(item.deletedAt != nil)

    try repo.restore(item)
    #expect(item.deletedAt == nil)
}

@MainActor
private func makeContext() throws -> ModelContext {
    let schema = Schema([Link.self, DebugItem.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [config])
    return ModelContext(container)
}
