import Foundation
import SwiftData

@MainActor
public final class MeetingAudioStorageRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func insert(_ storage: MeetingAudioStorage) throws {
        context.insert(storage)
        try context.save()
    }

    public func find(meetingID: UUID) throws -> MeetingAudioStorage? {
        var descriptor = FetchDescriptor<MeetingAudioStorage>(
            predicate: #Predicate { storage in
                storage.meetingID == meetingID
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func delete(_ storage: MeetingAudioStorage) throws {
        context.delete(storage)
        try context.save()
    }

    public func expired(asOf referenceDate: Date) throws -> [MeetingAudioStorage] {
        let descriptor = FetchDescriptor<MeetingAudioStorage>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try context.fetch(descriptor).filter { storage in
            guard storage.hasAudio, let expiresAt = storage.expiresAt else {
                return false
            }
            return expiresAt <= referenceDate
        }
    }

    public func markPruned(_ storage: MeetingAudioStorage) throws {
        storage.hasAudio = false
        storage.totalBytes = 0
        try context.save()
    }
}
