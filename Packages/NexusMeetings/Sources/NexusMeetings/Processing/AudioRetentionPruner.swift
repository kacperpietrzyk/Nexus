import Foundation

@MainActor
public final class AudioRetentionPruner {
    private let repository: MeetingAudioStorageRepository
    private let fileManager: FileManager
    private let clock: () -> Date

    public init(
        repository: MeetingAudioStorageRepository,
        fileManager: FileManager = .default,
        clock: @escaping () -> Date = { Date() }
    ) {
        self.repository = repository
        self.fileManager = fileManager
        self.clock = clock
    }

    @discardableResult
    public func runOnce() throws -> Int {
        let expired = try repository.expired(asOf: clock())
        var prunedCount = 0

        for storage in expired {
            if fileManager.fileExists(atPath: storage.folderURL.path) {
                try fileManager.removeItem(at: storage.folderURL)
            }
            try repository.markPruned(storage)
            prunedCount += 1
        }

        return prunedCount
    }
}
