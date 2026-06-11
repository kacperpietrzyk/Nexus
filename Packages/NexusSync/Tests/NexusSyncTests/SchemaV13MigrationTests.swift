import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusSync

/// V12 -> V13 migration: the Tranche-2 parity batch (spec
/// `2026-06-11-tranche2-v8-parity-batch.md` §3). Additive registration of the
/// `Cycle` + `ActivityEntry` entities plus four additive defaulted/optional
/// columns on `TaskItem`/`Note`.
///
/// The whole V12 -> V13 delta is lightweight-additive: a shipped-V12 on-disk
/// store physically lacks the two new tables and four new columns; the V13
/// build's lightweight inference adds them in one pass. There is NO data move
/// and NO backfill — every new field starts nil/defaulted and every new table
/// starts empty, so (unlike V9/V11/V12) this bump has NO marker-gated
/// post-open bootstrap step. The new `ItemKind.cycle` / `NoteRole.template`
/// raw enum cases ride existing `String`-backed columns and need no schema
/// change (the V12 `ItemKind.person` precedent).
@Suite struct SchemaV13MigrationTests {
    // MARK: - Schema shape

    @Test func v13AddsCycleAndActivityEntryToV12Models() {
        #expect(NexusSchemaV13.models.count == NexusSchemaV12.models.count + 2)
        #expect(NexusSchemaV13.models.contains { $0 == Cycle.self })
        #expect(NexusSchemaV13.models.contains { $0 == ActivityEntry.self })
    }

    @Test func v13VersionIsHigherThanV12() {
        #expect(NexusSchemaV13.versionIdentifier > NexusSchemaV12.versionIdentifier)
        #expect(NexusSchemaV13.versionIdentifier == Schema.Version(13, 0, 0))
    }

    @Test func migrationPlanIncludesV13Schema() {
        #expect(NexusMigrationPlan.schemas.contains { $0 == NexusSchemaV13.self })
    }

    /// The V12 -> V13 stage is lightweight-additive. It MUST stay
    /// `.lightweight`: the production split container drops the plan and
    /// relies on inference, so a `.custom` stage here would never run for
    /// real users (the architectural hazard the plan-type doc pins).
    @Test func v12ToV13StageIsLightweight() {
        let v12ToV13 = NexusMigrationPlan.stages
            .map { String(describing: $0) }
            .filter { $0.contains("V12") && $0.contains("V13") }
        #expect(v12ToV13.count == 1)
        #expect(v12ToV13.allSatisfy { $0.contains("lightweight") })
    }
}
