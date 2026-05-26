import Foundation

public struct RecordingMetadata: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var startedAt: TimeInterval
    public var durationSec: Int
    public var recordingCompletedAt: TimeInterval?
    public var transcriptCompletedAt: TimeInterval?
    public var processedAt: TimeInterval?
    public var processingStatus: String

    public init(
        id: String,
        title: String,
        startedAt: TimeInterval,
        durationSec: Int,
        recordingCompletedAt: TimeInterval? = nil,
        transcriptCompletedAt: TimeInterval? = nil,
        processedAt: TimeInterval? = nil,
        processingStatus: String
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.durationSec = durationSec
        self.recordingCompletedAt = recordingCompletedAt
        self.transcriptCompletedAt = transcriptCompletedAt
        self.processedAt = processedAt
        self.processingStatus = processingStatus
    }
}

public struct RecordingMetadataStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    public func writeStarted(meeting: Meeting, folder: URL) throws {
        try write(
            RecordingMetadata(
                id: meeting.id.uuidString,
                title: meeting.title,
                startedAt: meeting.startedAt.timeIntervalSince1970,
                durationSec: meeting.durationSec,
                processingStatus: meeting.processingStatus
            ),
            folder: folder
        )
    }

    public func markRecordingStopped(meeting: Meeting, folder: URL, stoppedAt: Date) throws {
        var metadata = try readOrMake(meeting: meeting, folder: folder)
        metadata.title = meeting.title
        metadata.durationSec = meeting.durationSec
        metadata.recordingCompletedAt = stoppedAt.timeIntervalSince1970
        metadata.processingStatus = meeting.processingStatus
        try write(metadata, folder: folder)
    }

    public func markTranscriptComplete(meeting: Meeting, folder: URL, completedAt: Date) throws {
        var metadata = try readOrMake(meeting: meeting, folder: folder)
        metadata.title = meeting.title
        metadata.durationSec = meeting.durationSec
        metadata.transcriptCompletedAt = completedAt.timeIntervalSince1970
        metadata.processingStatus = meeting.processingStatus
        try write(metadata, folder: folder)
    }

    public func markProcessed(meeting: Meeting, folder: URL, processedAt: Date) throws {
        var metadata = try readOrMake(meeting: meeting, folder: folder)
        metadata.title = meeting.title
        metadata.durationSec = meeting.durationSec
        metadata.transcriptCompletedAt = metadata.transcriptCompletedAt ?? processedAt.timeIntervalSince1970
        metadata.processedAt = processedAt.timeIntervalSince1970
        metadata.processingStatus = meeting.processingStatus
        try write(metadata, folder: folder)
    }

    public func read(folder: URL) throws -> RecordingMetadata {
        try decoder.decode(RecordingMetadata.self, from: Data(contentsOf: metadataURL(folder: folder)))
    }

    private func readOrMake(meeting: Meeting, folder: URL) throws -> RecordingMetadata {
        do {
            return try read(folder: folder)
        } catch {
            return RecordingMetadata(
                id: meeting.id.uuidString,
                title: meeting.title,
                startedAt: meeting.startedAt.timeIntervalSince1970,
                durationSec: meeting.durationSec,
                processingStatus: meeting.processingStatus
            )
        }
    }

    private func write(_ metadata: RecordingMetadata, folder: URL) throws {
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try encoder.encode(metadata).write(to: metadataURL(folder: folder), options: [.atomic])
    }

    private func metadataURL(folder: URL) -> URL {
        folder.appendingPathComponent("metadata.json")
    }
}
