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

    public init(autoCreated: [TaskItem], lowConfidence: [ExtractedActionItem]) {
        self.autoCreated = autoCreated
        self.lowConfidence = lowConfidence
    }
}

@MainActor
public final class ActionItemsStage {
    private let router: any MeetingProcessingRouting
    private let taskRepository: TaskItemRepository
    private let meetingRepository: MeetingRepository
    private let linkRepository: LinkRepository
    private let sourceID: String
    private let threshold: Double

    public init(
        router: any MeetingProcessingRouting,
        taskRepository: TaskItemRepository,
        meetingRepository: MeetingRepository,
        linkRepository: LinkRepository,
        sourceID: String,
        threshold: Double = 0.5
    ) {
        self.router = router
        self.taskRepository = taskRepository
        self.meetingRepository = meetingRepository
        self.linkRepository = linkRepository
        self.sourceID = sourceID
        self.threshold = threshold
    }

    public func run(
        meeting: Meeting,
        transcript: String,
        summary: String
    ) async throws -> ActionItemsStageOutput {
        let prompt = MeetingPromptBuilder.actionItemsPrompt(transcript: transcript, summary: summary)
        let request = AIRequest(
            prompt: prompt,
            capability: .generate,
            connectivity: .offlineOnly,
            cost: .free,
            providerPreference: .auto
        )
        let response = try await router.route(request)

        guard let extracted = Self.decodeExtractedItems(from: response.text) else {
            return ActionItemsStageOutput(autoCreated: [], lowConfidence: [])
        }

        var autoCreated: [TaskItem] = []
        var lowConfidence: [ExtractedActionItem] = []
        var createdIDs: [UUID] = []

        for item in extracted {
            let trimmedText = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if item.confidence >= threshold, trimmedText.isEmpty == false {
                let externalSourceID = Self.externalSourceID(
                    sourceID: sourceID,
                    meetingID: meeting.id,
                    actionText: trimmedText
                )
                let task: TaskItem
                if let existing = try existingTask(externalSourceID: externalSourceID) {
                    task = existing
                } else {
                    let created = TaskItem(title: trimmedText, status: .open)
                    created.externalSourceID = externalSourceID
                    try taskRepository.insert(created)
                    task = created
                }
                try linkRepository.findOrCreate(
                    from: (.meeting, meeting.id),
                    to: (.task, task.id),
                    linkKind: .actionItem
                )
                autoCreated.append(task)
                if createdIDs.contains(task.id) == false {
                    createdIDs.append(task.id)
                }
            } else {
                lowConfidence.append(item)
            }
        }

        if createdIDs.isEmpty == false, let saved = try meetingRepository.find(id: meeting.id) {
            var existingIDs = Set(saved.actionItemIDs)
            let newIDs = createdIDs.filter { existingIDs.insert($0).inserted }
            saved.actionItemIDs.append(contentsOf: newIDs)
            try meetingRepository.upsert(saved)
        }

        return ActionItemsStageOutput(autoCreated: autoCreated, lowConfidence: lowConfidence)
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
