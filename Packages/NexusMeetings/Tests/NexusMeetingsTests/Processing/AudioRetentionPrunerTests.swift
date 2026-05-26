import Foundation
import Testing

@testable import NexusMeetings

@MainActor
@Test func audioRetentionPrunerDeletesExpiredFolderAndMarksStoragePruned() throws {
    let context = try MeetingsTestSupport.makeContext()
    let repository = MeetingAudioStorageRepository(context: context)
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("NexusMeetingsPrunerTests-\(UUID().uuidString)", isDirectory: true)
    let audioFolder = root.appendingPathComponent("audio", isDirectory: true)
    try FileManager.default.createDirectory(at: audioFolder, withIntermediateDirectories: true)
    try Data("audio".utf8).write(to: audioFolder.appendingPathComponent("chunk.raw"))
    defer { try? FileManager.default.removeItem(at: root) }

    let meetingID = UUID()
    let storage = MeetingAudioStorage(
        meetingID: meetingID,
        folderURL: audioFolder,
        retentionPolicy: .never,
        totalBytes: 5
    )
    try repository.insert(storage)

    let pruner = AudioRetentionPruner(
        repository: repository,
        clock: { Date(timeIntervalSince1970: 1_800_000_000) }
    )

    let count = try pruner.runOnce()

    #expect(count == 1)
    #expect(FileManager.default.fileExists(atPath: audioFolder.path) == false)
    let fetched = try #require(try repository.find(meetingID: meetingID))
    #expect(fetched.hasAudio == false)
    #expect(fetched.totalBytes == 0)
}
