import Foundation
import Testing

@testable import NexusMeetings

@Test func crashRecoveryReturnsCandidatesUntilProcessedAtIsSet() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("NexusMeetingsCrashRecoveryTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let meetingID = UUID()
    let candidateFolder = root.appendingPathComponent("candidate", isDirectory: true)
    try FileManager.default.createDirectory(at: candidateFolder, withIntermediateDirectories: true)
    try Data(
        """
        {"id":"\(meetingID.uuidString)","title":"Recovered","startedAt":1700000000,"durationSec":120}
        """.utf8
    ).write(to: candidateFolder.appendingPathComponent("metadata.json"))

    let interruptedPostASRMeetingID = UUID()
    let interruptedPostASRFolder = root.appendingPathComponent("interrupted-post-asr", isDirectory: true)
    try FileManager.default.createDirectory(at: interruptedPostASRFolder, withIntermediateDirectories: true)
    try Data(
        """
        {
          "id":"\(interruptedPostASRMeetingID.uuidString)",
          "title":"Interrupted Post ASR",
          "startedAt":1700000050,
          "durationSec":240,
          "transcriptCompletedAt":1700000210
        }
        """.utf8
    ).write(to: interruptedPostASRFolder.appendingPathComponent("metadata.json"))

    let processedFolder = root.appendingPathComponent("processed", isDirectory: true)
    try FileManager.default.createDirectory(at: processedFolder, withIntermediateDirectories: true)
    try Data(
        """
        {
          "id":"\(UUID().uuidString)",
          "title":"Processed Metadata",
          "startedAt":1700000150,
          "durationSec":60,
          "transcriptCompletedAt":1700000210,
          "processedAt":1700000300
        }
        """.utf8
    ).write(to: processedFolder.appendingPathComponent("metadata.json"))

    let invalidUUIDFolder = root.appendingPathComponent("invalid", isDirectory: true)
    try FileManager.default.createDirectory(at: invalidUUIDFolder, withIntermediateDirectories: true)
    try Data(
        """
        {"id":"not-a-uuid","title":"Invalid","startedAt":1700000200,"durationSec":30}
        """.utf8
    ).write(to: invalidUUIDFolder.appendingPathComponent("metadata.json"))

    let recovery = CrashRecovery(rootFolder: root)
    let candidates = try recovery.recover()

    #expect(candidates.map(\.meetingID) == [interruptedPostASRMeetingID, meetingID])
    let candidate = try #require(candidates.last)
    #expect(candidate.meetingID == meetingID)
    #expect(candidate.title == "Recovered")
    #expect(candidate.startedAt == Date(timeIntervalSince1970: 1_700_000_000))
    #expect(candidate.durationSec == 120)
    #expect(candidate.audioFolder.standardizedFileURL == candidateFolder.standardizedFileURL)

    let interruptedPostASR = try #require(candidates.first)
    #expect(interruptedPostASR.meetingID == interruptedPostASRMeetingID)
    #expect(interruptedPostASR.title == "Interrupted Post ASR")
    #expect(interruptedPostASR.durationSec == 240)
}

@Test func crashRecoveryDoesNotTreatTranscriptFileAsDurableCompletionGate() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("NexusMeetingsCrashRecoveryLegacy-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let meetingID = UUID()
    let folder = root.appendingPathComponent("legacy-transcript", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(
        """
        {"id":"\(meetingID.uuidString)","title":"Legacy Transcript","startedAt":1700000100,"durationSec":60}
        """.utf8
    ).write(to: folder.appendingPathComponent("metadata.json"))
    try Data("[]".utf8).write(to: folder.appendingPathComponent("transcript.json"))

    let recovery = CrashRecovery(rootFolder: root)
    let candidates = try recovery.recover()

    #expect(candidates.map(\.meetingID) == [meetingID])
}

@Test func crashRecoveryMissingRootReturnsEmptyCandidates() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("NexusMeetingsCrashRecoveryMissing-\(UUID().uuidString)", isDirectory: true)

    let recovery = CrashRecovery(rootFolder: root)

    #expect(try recovery.recover().isEmpty)
}

@Test func crashRecoverySkipsMalformedMetadataAndRecoversValidFolders() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("NexusMeetingsCrashRecoveryMalformed-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let malformedFolder = root.appendingPathComponent("malformed", isDirectory: true)
    try FileManager.default.createDirectory(at: malformedFolder, withIntermediateDirectories: true)
    try Data("{".utf8).write(to: malformedFolder.appendingPathComponent("metadata.json"))

    let meetingID = UUID()
    let validFolder = root.appendingPathComponent("valid", isDirectory: true)
    try FileManager.default.createDirectory(at: validFolder, withIntermediateDirectories: true)
    try Data(
        """
        {"id":"\(meetingID.uuidString)","title":"Valid","startedAt":1700000300,"durationSec":90}
        """.utf8
    ).write(to: validFolder.appendingPathComponent("metadata.json"))

    let recovery = CrashRecovery(rootFolder: root)
    let candidates = try recovery.recover()

    #expect(candidates.map(\.meetingID) == [meetingID])
}
