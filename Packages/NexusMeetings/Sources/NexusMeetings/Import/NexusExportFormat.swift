import Foundation

public struct NexusExportFormat: Sendable {
    public init() {}

    public func plan(bundleURL: URL) throws -> CirclebackImportPlan {
        let fm = FileManager.default
        let manifestURL = bundleURL.appendingPathComponent("manifest.json")
        guard fm.fileExists(atPath: manifestURL.path) else {
            return CirclebackImportPlan(
                meetings: [],
                skipped: [
                    .init(
                        sourceFilePath: bundleURL.path,
                        reason: "Missing manifest.json — bundle does not look like a Nexus export"
                    )
                ])
        }
        let decoder = JSONDecoder()
        let manifest = try decoder.decode(ManifestDTO.self, from: try Data(contentsOf: manifestURL))
        let globalActions = try loadGlobalActions(bundleURL: bundleURL, decoder: decoder)
        return try parseMeetings(
            manifest: manifest,
            bundleURL: bundleURL,
            decoder: decoder,
            globalActions: globalActions
        )
    }

    private func loadGlobalActions(
        bundleURL: URL,
        decoder: JSONDecoder
    ) throws -> [Int: ActionItemDTO] {
        let url = bundleURL.appendingPathComponent("action-items.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let envelope = try decoder.decode(ActionItemsEnvelopeDTO.self, from: try Data(contentsOf: url))
        return Dictionary(envelope.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func parseMeetings(
        manifest: ManifestDTO,
        bundleURL: URL,
        decoder: JSONDecoder,
        globalActions: [Int: ActionItemDTO]
    ) throws -> CirclebackImportPlan {
        let fm = FileManager.default
        var meetings: [PlannedMeetingImport] = []
        var skipped: [SkippedMeetingReason] = []
        for entry in manifest.meetings {
            let meetingURL = bundleURL.appendingPathComponent("meetings/\(entry.id).json")
            guard fm.fileExists(atPath: meetingURL.path) else {
                skipped.append(
                    .init(
                        sourceFilePath: meetingURL.path,
                        reason: "Missing meeting record for id \(entry.id)"
                    ))
                continue
            }
            do {
                let dto = try decoder.decode(MeetingDTO.self, from: try Data(contentsOf: meetingURL))
                let transcriptURL = bundleURL.appendingPathComponent("transcripts/\(dto.linkId).json")
                let transcript: TranscriptDTO? =
                    fm.fileExists(atPath: transcriptURL.path)
                    ? try? decoder.decode(TranscriptDTO.self, from: try Data(contentsOf: transcriptURL))
                    : nil
                meetings.append(
                    try planMeeting(
                        dto: dto,
                        transcript: transcript,
                        globalActions: globalActions,
                        sourcePath: meetingURL.path
                    ))
            } catch {
                skipped.append(
                    .init(
                        sourceFilePath: meetingURL.path,
                        reason: error.localizedDescription
                    ))
            }
        }
        return CirclebackImportPlan(meetings: meetings, skipped: skipped)
    }

    private func planMeeting(
        dto: MeetingDTO,
        transcript: TranscriptDTO?,
        globalActions: [Int: ActionItemDTO],
        sourcePath: String
    ) throws -> PlannedMeetingImport {
        let createdAt = try parseDate(dto.createdAt)
        let durationSec = Int(dto.duration.rounded())
        let startedAt = createdAt.addingTimeInterval(-Double(durationSec))
        // endedAt == startedAt + durationSec == createdAt by construction.
        let endedAt = createdAt
        let segments: [PlannedTranscriptSegment] = (transcript?.transcript ?? []).map {
            PlannedTranscriptSegment(speaker: $0.speaker, text: $0.text, startSec: $0.timestamp)
        }
        let transcriptText = segments.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
        let attendees = dto.attendees.map { PlannedAttendee(name: $0.name, email: $0.email) }
        let actions = planActions(dto.actionItems, globalActions: globalActions)
        return PlannedMeetingImport(
            externalID: dto.id,
            externalLinkID: dto.linkId,
            externalSourceID: CirclebackExternalRef.meeting(id: dto.id),
            title: dto.name,
            startedAt: startedAt,
            endedAt: endedAt,
            circlebackCreatedAt: createdAt,
            durationSec: durationSec,
            summaryMarkdown: dto.notes ?? "",
            attendees: attendees,
            transcriptText: transcriptText,
            transcriptSegments: segments,
            actionItems: actions,
            sourceFilePath: sourcePath
        )
    }

    private func planActions(
        _ nested: [NestedActionDTO],
        globalActions: [Int: ActionItemDTO]
    ) -> [PlannedActionItem] {
        nested.map { n in
            if let g = globalActions[n.id] {
                return PlannedActionItem(
                    externalID: g.id,
                    externalSourceID: CirclebackExternalRef.actionItem(id: g.id),
                    title: g.title,
                    description: g.description,
                    assigneeName: g.assignee?.name ?? n.assignee?.name,
                    assigneeEmail: g.assignee?.email ?? n.assignee?.email,
                    status: g.status.uppercased() == "DONE" ? .done : .pending,
                    completedAt: g.completedAt.flatMap { try? parseDate($0) },
                    circlebackCreatedAt: try? parseDate(g.createdAt)
                )
            }
            return PlannedActionItem(
                externalID: n.id,
                externalSourceID: CirclebackExternalRef.actionItem(id: n.id),
                title: n.title,
                description: n.description,
                assigneeName: n.assignee?.name,
                assigneeEmail: n.assignee?.email,
                status: n.status.uppercased() == "DONE" ? .done : .pending,
                completedAt: nil,
                circlebackCreatedAt: nil
            )
        }
    }

    private func parseDate(_ raw: String) throws -> Date {
        if let date = ISO8601DateFormatter.withFractionalSeconds.date(from: raw) { return date }
        if let date = ISO8601DateFormatter().date(from: raw) { return date }
        throw NSError(
            domain: "NexusExportFormat",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unparseable ISO8601 date: \(raw)"]
        )
    }
}

// MARK: - Private DTOs

private struct ManifestDTO: Decodable {
    let schemaVersion: Int
    let source: String
    let exportedAt: String
    let counts: CountsDTO
    let meetings: [ManifestMeetingDTO]
}

private struct CountsDTO: Decodable {
    let meetings: Int
    let transcripts: Int
    let actionItems: Int
}

private struct ManifestMeetingDTO: Decodable {
    let id: Int
    let linkId: String
    let title: String
    let createdAt: String
}

// Circleback's ReadMeetings shape uses "name" at the top level;
// the manifest index and synthetic tests use "title". Accept both.
private struct MeetingDTO: Decodable {
    let id: Int
    let linkId: String
    let name: String
    let createdAt: String
    let duration: Double
    let notes: String?
    let attendees: [AttendeeDTO]
    let actionItems: [NestedActionDTO]

    private enum CodingKeys: String, CodingKey {
        case id, linkId, name, title, createdAt, duration, notes, attendees, actionItems
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        linkId = try c.decode(String.self, forKey: .linkId)
        // Real Circleback ReadMeetings uses "name"; synthetic fixtures use "title".
        if let n = try c.decodeIfPresent(String.self, forKey: .name) {
            name = n
        } else {
            name = try c.decode(String.self, forKey: .title)
        }
        createdAt = try c.decode(String.self, forKey: .createdAt)
        duration = try c.decode(Double.self, forKey: .duration)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        attendees = try c.decode([AttendeeDTO].self, forKey: .attendees)
        actionItems = try c.decode([NestedActionDTO].self, forKey: .actionItems)
    }
}

private struct AttendeeDTO: Decodable {
    let name: String
    let email: String?
}

private struct NestedActionDTO: Decodable {
    let id: Int
    let title: String
    let description: String
    let assignee: AttendeeDTO?
    let status: String
}

private struct TranscriptDTO: Decodable {
    let meetingId: String
    let meetingName: String?
    let transcript: [TranscriptSegmentDTO]
}

private struct TranscriptSegmentDTO: Decodable {
    let speaker: String
    let text: String
    let timestamp: Double
}

private struct ActionItemsEnvelopeDTO: Decodable {
    let schemaVersion: Int
    let exportedAt: String
    let items: [ActionItemDTO]
}

private struct ActionItemDTO: Decodable {
    let id: Int
    let title: String
    let description: String
    let status: String
    let completedAt: String?
    let createdAt: String
    let assignee: GlobalAssigneeDTO?
    let meeting: ActionMeetingRefDTO
}

private struct GlobalAssigneeDTO: Decodable {
    let profileId: Int?
    let name: String
    let email: String?
}

private struct ActionMeetingRefDTO: Decodable {
    let id: Int
    let name: String
    let createdAt: String
}

extension ISO8601DateFormatter {
    // ISO8601DateFormatter is not Sendable, but this instance is never mutated after init.
    nonisolated(unsafe) static let withFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
