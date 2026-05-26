import Foundation
import SwiftData
import Testing

@testable import NexusMeetings
@testable import NexusSync

@MainActor
@Test func localOnlyAudioStorageStoreIsClassifiedAsUserDataDuringMigration() throws {
    let sourceBase = temporaryStoreURL(prefix: "nexus-meeting-audio-source")
    let destinationBase = temporaryStoreURL(prefix: "nexus-meeting-audio-destination")
    defer {
        cleanupStores(at: [
            sourceBase,
            NexusModelContainer.localOnlyStoreURL(for: sourceBase),
            destinationBase,
            NexusModelContainer.localOnlyStoreURL(for: destinationBase),
        ])
    }
    let meetingID = UUID()
    let folderURL = URL(fileURLWithPath: "/tmp/\(meetingID.uuidString)")
    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)

    do {
        let container = try NexusModelContainer.make(
            environment: MeetingsMigrationTestEnvironment(),
            fileURL: sourceBase,
            extraModels: [Meeting.self],
            localOnlyExtraModels: [MeetingAudioStorage.self]
        )
        let context = ModelContext(container)
        context.insert(
            MeetingAudioStorage(
                meetingID: meetingID,
                folderURL: folderURL,
                retentionPolicy: .days30,
                totalBytes: 512,
                hasAudio: true,
                createdAt: createdAt
            ))
        try context.save()
    }

    do {
        _ = try NexusModelContainer.make(
            environment: MeetingsMigrationTestEnvironment(),
            fileURL: destinationBase,
            extraModels: [Meeting.self],
            localOnlyExtraModels: [MeetingAudioStorage.self]
        )
    }

    let migrationResult = try NexusModelContainer.migrateStoreFilesIfNeeded(
        from: NexusModelContainer.localOnlyStoreURL(for: sourceBase),
        to: NexusModelContainer.localOnlyStoreURL(for: destinationBase)
    )

    #expect(migrationResult == .replacedEmptyDestination)

    let destinationContainer = try NexusModelContainer.make(
        environment: MeetingsMigrationTestEnvironment(),
        fileURL: destinationBase,
        extraModels: [Meeting.self],
        localOnlyExtraModels: [MeetingAudioStorage.self]
    )
    let destinationContext = ModelContext(destinationContainer)
    let fetched = try destinationContext.fetch(FetchDescriptor<MeetingAudioStorage>())
    let storage = try #require(fetched.first)

    #expect(fetched.count == 1)
    #expect(storage.meetingID == meetingID)
    #expect(storage.folderURL == folderURL)
    #expect(storage.retentionPolicy == MeetingAudioStorage.RetentionPolicy.days30.rawValue)
    #expect(storage.totalBytes == 512)
    #expect(storage.createdAt == createdAt)
}

private struct MeetingsMigrationTestEnvironment: NexusEnvironmentProviding {
    let cloudKitEnabled = false
    let cloudKitContainerIdentifier = NexusEnvironment.containerIdentifier
}

private func temporaryStoreURL(prefix: String) -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("\(prefix)-\(UUID().uuidString).store")
}

private func cleanupStores(at urls: [URL]) {
    for url in urls {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
    }
}
