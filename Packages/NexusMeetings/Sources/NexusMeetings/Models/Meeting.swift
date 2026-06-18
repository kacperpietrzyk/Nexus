import Foundation
import NexusCore
import SwiftData

@Model
public final class Meeting: Linkable, Searchable {
    public var id: UUID = UUID()
    public var kind: ItemKind = ItemKind.meeting
    public var title: String = ""
    public var startedAt: Date = Date()
    public var durationSec: Int = 0
    public var endedAt: Date?
    public var appBundleID: String?
    public var calendarEventID: String?
    public var detectionSource: String = MeetingDetectionSource.manual.rawValue
    public var processingStatus: String = MeetingProcessingStatus.recording.rawValue
    public var processedAt: Date?
    @Attribute(.allowsCloudEncryption) public var transcriptText: String = ""
    @Attribute(.allowsCloudEncryption) public var summaryText: String = ""
    public var segmentsJSON: Data = Data("[]".utf8)
    public var participantsJSON: Data?
    public var actionItemIDs: [UUID] = []
    public var languageCode: String?
    public var providerProfile: String = ""
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date?
    public var externalSourceID: String?
    /// Whether the user has pinned this meeting to the Today dashboard.
    /// Additive/defaulted — CloudKit-safe lightweight migration.
    public var isPinned: Bool = false
    /// When the meeting was most recently pinned. nil if never pinned.
    public var pinnedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        startedAt: Date,
        durationSec: Int = 0,
        endedAt: Date? = nil,
        appBundleID: String? = nil,
        calendarEventID: String? = nil,
        detectionSource: MeetingDetectionSource,
        processingStatus: MeetingProcessingStatus = .recording,
        processedAt: Date? = nil,
        transcriptText: String = "",
        summaryText: String = "",
        segmentsJSON: Data = Data("[]".utf8),
        participantsJSON: Data? = nil,
        actionItemIDs: [UUID] = [],
        languageCode: String? = nil,
        providerProfile: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = .meeting
        self.title = title
        self.startedAt = startedAt
        self.durationSec = durationSec
        self.endedAt = endedAt
        self.appBundleID = appBundleID
        self.calendarEventID = calendarEventID
        self.detectionSource = detectionSource.rawValue
        self.processingStatus = processingStatus.rawValue
        self.processedAt = processedAt
        self.transcriptText = transcriptText
        self.summaryText = summaryText
        self.segmentsJSON = segmentsJSON
        self.participantsJSON = participantsJSON
        self.actionItemIDs = actionItemIDs
        self.languageCode = languageCode
        self.providerProfile = providerProfile
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = nil
    }

    public var searchableText: String {
        [title, transcriptText, summaryText]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
