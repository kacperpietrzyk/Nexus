import Foundation

public struct RecoveredMeetingCandidate: Equatable, Sendable {
    public let meetingID: UUID
    public let title: String
    public let startedAt: Date
    public let durationSec: Int
    public let audioFolder: URL

    public init(
        meetingID: UUID,
        title: String,
        startedAt: Date,
        durationSec: Int,
        audioFolder: URL
    ) {
        self.meetingID = meetingID
        self.title = title
        self.startedAt = startedAt
        self.durationSec = durationSec
        self.audioFolder = audioFolder
    }
}

public struct CrashRecovery {
    private let rootFolder: URL
    private let fileManager: FileManager

    public init(rootFolder: URL, fileManager: FileManager = .default) {
        self.rootFolder = rootFolder
        self.fileManager = fileManager
    }

    public func recover() throws -> [RecoveredMeetingCandidate] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootFolder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }

        let folders = try fileManager.contentsOfDirectory(
            at: rootFolder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var candidates: [RecoveredMeetingCandidate] = []
        for folder in folders {
            let values = try folder.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }

            let metadataURL = folder.appendingPathComponent("metadata.json")
            guard fileManager.fileExists(atPath: metadataURL.path) else {
                continue
            }

            guard
                let metadata = try? JSONDecoder().decode(
                    RecoveryMetadata.self,
                    from: Data(contentsOf: metadataURL)
                )
            else {
                continue
            }
            guard let meetingID = UUID(uuidString: metadata.id) else {
                continue
            }
            guard metadata.processedAt == nil else {
                continue
            }

            candidates.append(
                RecoveredMeetingCandidate(
                    meetingID: meetingID,
                    title: metadata.title,
                    startedAt: Date(timeIntervalSince1970: metadata.startedAt),
                    durationSec: metadata.durationSec,
                    audioFolder: folder
                )
            )
        }

        return candidates.sorted {
            if $0.startedAt != $1.startedAt {
                return $0.startedAt > $1.startedAt
            }
            if $0.title != $1.title {
                return $0.title < $1.title
            }
            return $0.meetingID.uuidString < $1.meetingID.uuidString
        }
    }
}

private struct RecoveryMetadata: Decodable {
    let id: String
    let title: String
    let startedAt: TimeInterval
    let durationSec: Int
    let transcriptCompletedAt: TimeInterval?
    let processedAt: TimeInterval?
}
