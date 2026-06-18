import Foundation
import SwiftData

@MainActor
public final class MeetingRepository {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func insert(_ meeting: Meeting) throws {
        context.insert(meeting)
        try context.save()
    }

    public func upsert(_ meeting: Meeting) throws {
        guard let existing = try find(id: meeting.id) else {
            try insert(meeting)
            return
        }

        existing.title = meeting.title
        existing.startedAt = meeting.startedAt
        existing.durationSec = meeting.durationSec
        existing.endedAt = meeting.endedAt
        existing.appBundleID = meeting.appBundleID
        existing.calendarEventID = meeting.calendarEventID
        existing.detectionSource = meeting.detectionSource
        existing.processingStatus = meeting.processingStatus
        existing.processedAt = meeting.processedAt
        existing.transcriptText = meeting.transcriptText
        existing.summaryText = meeting.summaryText
        existing.segmentsJSON = meeting.segmentsJSON
        existing.participantsJSON = meeting.participantsJSON
        existing.actionItemIDs = meeting.actionItemIDs
        existing.languageCode = meeting.languageCode
        existing.providerProfile = meeting.providerProfile
        existing.externalSourceID = meeting.externalSourceID
        existing.deletedAt = meeting.deletedAt
        existing.updatedAt = Date()
        try context.save()
    }

    public func find(id: UUID) throws -> Meeting? {
        var descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { meeting in
                meeting.id == id
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func allChronological() throws -> [Meeting] {
        let descriptor = FetchDescriptor<Meeting>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    public func recent(limit: Int) throws -> [Meeting] {
        var descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { meeting in
                meeting.deletedAt == nil
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    /// Searches non-deleted meetings for `query`, newest first.
    ///
    /// `speaker == nil` (default) keeps today's behaviour exactly: a substring,
    /// case/diacritic-insensitive match over `searchableText` (title + transcript
    /// + summary).
    ///
    /// `speaker != nil` (spec §6) narrows to meetings where at least one of *that
    /// speaker's* segments contains the query. The corpus deliberately shifts from
    /// `searchableText` to per-speaker segment text, so a hit means the named
    /// speaker actually said the query — not merely that they were present.
    /// `speaker` matches either the raw diarized token (`Speaker_N`, `Me`) or the
    /// user-assigned `displayName` (see `MergeStage.segments(_:forSpeaker:participants:)`).
    public func search(
        query: String,
        limit: Int,
        speaker: String? = nil,
        batchSize: Int = 200
    ) throws -> [Meeting] {
        guard limit > 0 else { return [] }

        let pageSize = max(limit, batchSize)
        var offset = 0
        var matches: [Meeting] = []

        while matches.count < limit {
            var descriptor = FetchDescriptor<Meeting>(
                predicate: #Predicate { meeting in
                    meeting.deletedAt == nil
                },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            descriptor.fetchLimit = pageSize
            descriptor.fetchOffset = offset

            let page = try context.fetch(descriptor)
            guard !page.isEmpty else { break }

            for meeting in page where Self.meeting(meeting, matches: query, speaker: speaker) {
                matches.append(meeting)
                if matches.count == limit { break }
            }

            if page.count < pageSize { break }
            offset += page.count
        }

        return matches
    }

    private static func meeting(_ meeting: Meeting, matches query: String, speaker: String?) -> Bool {
        guard let speaker else {
            return meeting.searchableText.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
        }

        let segments = (try? MeetingSpeakerSegment.decode(meeting.segmentsJSON)) ?? []
        let participants = (try? MeetingParticipant.decode(meeting.participantsJSON ?? Data())) ?? []
        return MergeStage.segments(segments, forSpeaker: speaker, participants: participants)
            .contains {
                $0.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
    }

    public func range(from start: Date, to end: Date) throws -> [Meeting] {
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { meeting in
                meeting.startedAt >= start && meeting.startedAt <= end
            },
            sortBy: [SortDescriptor(\.startedAt, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    public func delete(id: UUID) throws {
        if let meeting = try find(id: id) {
            context.delete(meeting)
        }
        if let storage = try MeetingAudioStorageRepository(context: context).find(meetingID: id) {
            // Remove the on-disk audio folder before dropping the storage row. Deleting only the
            // row orphans me.wav/others.wav/metadata.json forever, since AudioRetentionPruner
            // reaches recordings via MeetingAudioStorage rows and this one is now gone. Matches
            // the pruner's disposal; best-effort so a file error never blocks the DB delete.
            try? FileManager.default.removeItem(at: storage.folderURL)
            context.delete(storage)
        }
        try context.save()
    }

    public func allExternalSourceIDs(withPrefix prefix: String) throws -> [String] {
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { meeting in
                meeting.externalSourceID != nil
            }
        )
        return try context.fetch(descriptor).compactMap(\.externalSourceID).filter {
            $0.hasPrefix(prefix)
        }
    }

    /// Distinct, user-assigned participant display names across all meetings,
    /// sorted case/diacritic-insensitively. Powers the rename autocomplete so a
    /// person named once can be picked again instead of retyped (Circleback
    /// parity). Names left at their auto-generated `speakerID` default (e.g.
    /// "Speaker 1") are skipped — only genuinely-named people are suggested.
    public func distinctParticipantNames() throws -> [String] {
        var unique: Set<String> = []
        for meeting in try allChronological() {
            let participants =
                (try? MeetingParticipant.decode(meeting.participantsJSON ?? Data())) ?? []
            for participant in participants {
                let name = participant.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, name != participant.speakerID else { continue }
                unique.insert(name)
            }
        }
        return unique.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public func updateProcessingStatus(_ status: String, for meetingID: UUID) throws {
        guard let meeting = try find(id: meetingID) else { return }
        meeting.processingStatus = status
        meeting.updatedAt = Date()
        try context.save()
    }

    public func setPinned(_ meeting: Meeting, _ pinned: Bool) throws {
        meeting.isPinned = pinned
        meeting.pinnedAt = pinned ? Date() : nil
        meeting.updatedAt = Date()
        try context.save()
    }
}
