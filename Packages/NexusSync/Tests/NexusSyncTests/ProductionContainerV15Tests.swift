import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusSync

/// Gate for the V15 release-blocker: the LIVE production container must register
/// `Organization` + `ProjectKeyDate`. The existing `SchemaV15MigrationTests` only
/// assert static model lists — they never BUILD the container, so they miss the bug
/// where the container binding stayed pinned to `NexusSchemaV14` and the new
/// entities were never registered (first touch traps).
///
/// These tests build the REAL container via the same factory the apps use
/// (`makeInMemory`, the in-memory mirror of `make`), exercising BOTH the
/// single-configuration path AND the split / inference path that production
/// actually takes (a composition-time synced extra like `Meeting` forces the
/// assembled-schema inference open, so any custom migration stage is skipped).
@Suite("Production container registers V15 entities")
struct ProductionContainerV15Tests {
    /// Mirrors the launch `rebuildSearchIndex` path: fetch `Organization.self`
    /// (which traps if the entity isn't registered) and insert + fetch a
    /// `ProjectKeyDate`. Plain single-config build (no extras).
    @MainActor
    @Test func registersOrganizationAndKeyDateInBaselineContainer() throws {
        let container = try NexusModelContainer.makeInMemory()
        let context = ModelContext(container)

        // Fetch Organization — the launch rebuildSearchIndex touches this type.
        // An unregistered entity traps here; a registered one yields [].
        let organizations = try context.fetch(FetchDescriptor<Organization>())
        #expect(organizations.isEmpty)

        // Touch ProjectKeyDate: insert + fetch round-trip.
        let keyDate = ProjectKeyDate(
            projectID: UUID(),
            anchorKey: "T0",
            label: "Contract signing",
            date: .now,
            isContractual: true
        )
        context.insert(keyDate)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<ProjectKeyDate>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.anchorKey == "T0")
    }

    /// Production reality: a composition-time SYNCED extra (stand-in for `Meeting`)
    /// is supplied, which drives `makeContainer` down the assembled-schema inference
    /// branch (`hasEffectiveExtraModels == true`) where the staged `NexusMigrationPlan`
    /// is intentionally dropped. The V15 entities must STILL be registered via the
    /// lightweight inference open — this is the exact path the app launches on.
    @MainActor
    @Test func registersV15EntitiesOnInferenceBranchWithSyncedExtra() throws {
        let container = try NexusModelContainer.makeInMemory(extraModels: [StubSyncedExtra.self])
        let context = ModelContext(container)

        let organizations = try context.fetch(FetchDescriptor<Organization>())
        #expect(organizations.isEmpty)

        let org = Organization(name: "Acme")
        context.insert(org)
        let keyDate = ProjectKeyDate(
            projectID: UUID(),
            anchorKey: "PO",
            label: "Acceptance protocol",
            date: .now
        )
        context.insert(keyDate)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Organization>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<ProjectKeyDate>()).count == 1)

        // The synced extra must still round-trip alongside the V15 entities.
        context.insert(StubSyncedExtra(label: "meeting-stub"))
        try context.save()
        #expect(try context.fetch(FetchDescriptor<StubSyncedExtra>()).count == 1)
    }

    /// Gate for V16: the in-memory container must persist the new `isPinned` /
    /// `pinnedAt` fields on `Project`. Confirms the schema bump is wired end-to-end.
    @MainActor
    @Test func v16ContainerPersistsPinFields() throws {
        let container = try NexusModelContainer.makeInMemory()
        let context = ModelContext(container)
        let project = Project(name: "Pinned")
        project.isPinned = true
        project.pinnedAt = .now
        context.insert(project)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<Project>())
        #expect(fetched.first?.isPinned == true)
        #expect(fetched.first?.pinnedAt != nil)
    }
}
