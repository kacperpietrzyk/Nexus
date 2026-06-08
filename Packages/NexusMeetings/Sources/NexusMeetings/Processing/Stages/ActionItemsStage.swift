import CryptoKit
import Foundation
import NexusAI
import NexusCore
import SwiftData

public struct ExtractedActionItem: Codable, Sendable, Equatable {
    public let text: String
    public let assigneeHint: String?
    public let dueHint: String?
    public let confidence: Double

    public init(
        text: String,
        assigneeHint: String?,
        dueHint: String?,
        confidence: Double
    ) {
        self.text = text
        self.assigneeHint = assigneeHint
        self.dueHint = dueHint
        self.confidence = confidence
    }
}

public struct ActionItemsStageOutput {
    public let autoCreated: [TaskItem]
    public let lowConfidence: [ExtractedActionItem]
    /// High-confidence items whose `assigneeHint` names someone other than the
    /// user. Single-user correctness boundary (§4.1/I1): another person's
    /// action item is NOT your task, so it is never materialized. Held here as
    /// a "not-mine" channel; a future People wire-up may link these to a
    /// `Person` via `LinkKind.mentions` (never as an assignee).
    public let notMine: [ExtractedActionItem]

    public init(
        autoCreated: [TaskItem],
        lowConfidence: [ExtractedActionItem],
        notMine: [ExtractedActionItem] = []
    ) {
        self.autoCreated = autoCreated
        self.lowConfidence = lowConfidence
        self.notMine = notMine
    }
}

@MainActor
public final class ActionItemsStage {
    /// First-person aliases that mark an action item as the user's own. Used as
    /// the default for `userAliases` so an `assigneeHint` like "Me"/"I" still
    /// materializes a task in a single-user app. Names not in this set are
    /// treated as someone else and routed to the not-mine channel.
    public static let defaultUserAliases: Set<String> = ["me", "i", "myself", "my", "mine"]

    private let router: any MeetingProcessingRouting
    private let taskRepository: TaskItemRepository
    private let meetingRepository: MeetingRepository
    private let linkRepository: LinkRepository
    private let sourceID: String
    private let threshold: Double
    private let dateExtractor: (any DateExtracting)?
    private let userAliases: Set<String>

    public init(
        router: any MeetingProcessingRouting,
        taskRepository: TaskItemRepository,
        meetingRepository: MeetingRepository,
        linkRepository: LinkRepository,
        sourceID: String,
        threshold: Double = 0.5,
        dateExtractor: (any DateExtracting)? = nil,
        userAliases: Set<String> = ActionItemsStage.defaultUserAliases
    ) {
        self.router = router
        self.taskRepository = taskRepository
        self.meetingRepository = meetingRepository
        self.linkRepository = linkRepository
        self.sourceID = sourceID
        self.threshold = threshold
        self.dateExtractor = dateExtractor
        self.userAliases = Set(userAliases.map { $0.lowercased() })
    }

    public func run(
        meeting: Meeting,
        transcript: String,
        summary: String,
        screenContext: String? = nil
    ) async throws -> ActionItemsStageOutput {
        let prompt = MeetingPromptBuilder.actionItemsPrompt(
            transcript: transcript,
            summary: summary,
            screenContext: screenContext
        )
        let request = AIRequest(
            prompt: prompt,
            capability: .generate,
            connectivity: .offlineOnly,
            cost: .free,
            providerPreference: .auto
        )
        let response = try await router.route(request)

        guard let extracted = Self.decodeExtractedItems(from: response.text) else {
            return ActionItemsStageOutput(autoCreated: [], lowConfidence: [], notMine: [])
        }

        var autoCreated: [TaskItem] = []
        var lowConfidence: [ExtractedActionItem] = []
        var notMine: [ExtractedActionItem] = []
        var createdIDs: [UUID] = []
        let locale = Self.locale(for: meeting)

        for item in extracted {
            let trimmedText = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard item.confidence >= threshold, trimmedText.isEmpty == false else {
                lowConfidence.append(item)
                continue
            }

            // Single-user boundary (§4.1/I1): only materialize items assigned to
            // the user (or with no explicit assignee). Someone else's item is
            // routed to the not-mine channel — never a task, and `assigneeHint`
            // is never stored on a `TaskItem` (I2).
            guard isMine(assigneeHint: item.assigneeHint) else {
                notMine.append(item)
                continue
            }

            let task = try await materializeTask(
                meeting: meeting,
                item: item,
                trimmedText: trimmedText,
                locale: locale
            )
            try linkRepository.findOrCreate(
                from: (.meeting, meeting.id),
                to: (.task, task.id),
                linkKind: .actionItem
            )
            autoCreated.append(task)
            if createdIDs.contains(task.id) == false {
                createdIDs.append(task.id)
            }
        }

        if createdIDs.isEmpty == false, let saved = try meetingRepository.find(id: meeting.id) {
            var existingIDs = Set(saved.actionItemIDs)
            let newIDs = createdIDs.filter { existingIDs.insert($0).inserted }
            saved.actionItemIDs.append(contentsOf: newIDs)
            try meetingRepository.upsert(saved)
        }

        return ActionItemsStageOutput(
            autoCreated: autoCreated,
            lowConfidence: lowConfidence,
            notMine: notMine
        )
    }

    /// Returns the existing deduped task for this action item, or creates a new
    /// one. For newly-created tasks only, resolves a free-text `dueHint` into a
    /// concrete `dueAt` (unresolved hint -> task without `dueAt`, not an error).
    /// A dedup hit is returned untouched so an existing `dueAt` is never clobbered.
    private func materializeTask(
        meeting: Meeting,
        item: ExtractedActionItem,
        trimmedText: String,
        locale: Locale
    ) async throws -> TaskItem {
        let externalSourceID = Self.externalSourceID(
            sourceID: sourceID,
            meetingID: meeting.id,
            actionText: trimmedText
        )
        if let existing = try existingTask(externalSourceID: externalSourceID) {
            return existing
        }
        let created = TaskItem(title: trimmedText, status: .open)
        created.externalSourceID = externalSourceID
        if let hint = item.dueHint, let extractor = dateExtractor {
            created.dueAt = await extractor.date(from: hint, now: meeting.startedAt, locale: locale)
        }
        try taskRepository.insert(created)
        return created
    }

    /// Whether an action item with the given `assigneeHint` belongs to the user.
    /// `nil`/blank hint -> mine; a hint matching a known user alias -> mine;
    /// any other named assignee -> not mine.
    private func isMine(assigneeHint: String?) -> Bool {
        guard let hint = assigneeHint?.trimmingCharacters(in: .whitespacesAndNewlines),
            hint.isEmpty == false
        else {
            return true
        }
        return userAliases.contains(hint.lowercased())
    }

    private static func locale(for meeting: Meeting) -> Locale {
        if let code = meeting.languageCode, code.isEmpty == false, code != "und" {
            return Locale(identifier: code)
        }
        return Locale.current
    }

    private func existingTask(externalSourceID: String) throws -> TaskItem? {
        var descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.externalSourceID == externalSourceID && task.deletedAt == nil
            }
        )
        descriptor.fetchLimit = 1
        return try taskRepository.context.fetch(descriptor).first
    }

    private static func externalSourceID(sourceID: String, meetingID: UUID, actionText: String) -> String {
        let normalizedText = normalizedActionText(actionText)
        let digest = SHA256.hash(data: Data(normalizedText.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(sourceID):\(meetingID.uuidString):\(hex)"
    }

    private static func normalizedActionText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func decodeExtractedItems(from text: String) -> [ExtractedActionItem]? {
        let decoder = JSONDecoder()
        for candidate in jsonArrayCandidates(from: text) {
            if let extracted = try? decoder.decode([ExtractedActionItem].self, from: Data(candidate.utf8)) {
                return extracted
            }
        }
        return nil
    }

    private static func jsonArrayCandidates(from text: String) -> [String] {
        fencedJSONCandidates(from: text) + balancedArrayCandidates(from: text)
    }

    private static func fencedJSONCandidates(from text: String) -> [String] {
        var candidates: [String] = []
        var searchStart = text.startIndex

        while let fenceStart = text[searchStart...].range(of: "```") {
            let infoStart = fenceStart.upperBound
            guard let infoEnd = text[infoStart...].firstIndex(of: "\n") else {
                break
            }
            let info = text[infoStart..<infoEnd].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let contentStart = text.index(after: infoEnd)
            guard let fenceEnd = text[contentStart...].range(of: "```") else {
                break
            }

            if info.isEmpty || info == "json" {
                candidates.append(contentsOf: balancedArrayCandidates(from: String(text[contentStart..<fenceEnd.lowerBound])))
            }
            searchStart = fenceEnd.upperBound
        }

        return candidates
    }

    private static func balancedArrayCandidates(from text: String) -> [String] {
        var candidates: [String] = []
        var index = text.startIndex

        while index < text.endIndex {
            guard text[index] == "[" else {
                index = text.index(after: index)
                continue
            }

            var cursor = index
            var depth = 0
            var isInString = false
            var isEscaped = false

            while cursor < text.endIndex {
                let character = text[cursor]

                if isInString {
                    if isEscaped {
                        isEscaped = false
                    } else if character == "\\" {
                        isEscaped = true
                    } else if character == "\"" {
                        isInString = false
                    }
                } else if character == "\"" {
                    isInString = true
                } else if character == "[" {
                    depth += 1
                } else if character == "]" {
                    depth -= 1
                    if depth == 0 {
                        candidates.append(String(text[index...cursor]))
                        index = text.index(after: cursor)
                        break
                    }
                }

                cursor = text.index(after: cursor)
            }

            if cursor >= text.endIndex {
                break
            }
        }

        return candidates
    }
}
