import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusSync

@MainActor
@Test func schemaV7IncludesModelManifestAndDownloadEvent() {
    let ids = NexusSchemaV7.models.map { ObjectIdentifier($0) }
    #expect(ids.contains(ObjectIdentifier(ModelManifest.self)))
    #expect(ids.contains(ObjectIdentifier(ModelDownloadEvent.self)))
}

@MainActor
@Test func schemaV7VersionIsHigherThanV6() {
    #expect(NexusSchemaV7.versionIdentifier > NexusSchemaV6.versionIdentifier)
}

@MainActor
@Test func migrationPlanIncludesV6ToV7Stage() {
    let stages = NexusMigrationPlan.stages
    #expect(stages.contains { String(describing: $0).contains("V6") && String(describing: $0).contains("V7") })
}

@MainActor
@Test func freshV7StoreAllowsModelManifestAndEventInserts() throws {
    let schema = Schema(versionedSchema: NexusSchemaV7.self)
    let container = try ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
    let ctx = ModelContext(container)
    ctx.insert(
        ModelManifest(
            id: "qwen3.5-4b-instruct-4bit",
            hfPath: "mlx-community/Qwen3.5-4B-Instruct-4bit",
            family: "qwen3.5",
            displayName: "Qwen 3.5 4B",
            sizeGB: 3.2,
            recommendedRAMGB: 16,
            contextLength: 16_384,
            supportsTools: true,
            supportsVision: false,
            supportedLocales: ["en", "pl"],
            purpose: "chat"
        )
    )
    ctx.insert(
        ModelDownloadEvent(
            modelManifestID: "qwen3.5-4b-instruct-4bit",
            kind: "completed",
            occurredAt: Date(),
            bytesTransferred: 3_200_000_000,
            durationSeconds: 180.0,
            errorMessage: nil
        )
    )
    try ctx.save()
    #expect(try ctx.fetch(FetchDescriptor<ModelManifest>()).count == 1)
    #expect(try ctx.fetch(FetchDescriptor<ModelDownloadEvent>()).count == 1)
}
