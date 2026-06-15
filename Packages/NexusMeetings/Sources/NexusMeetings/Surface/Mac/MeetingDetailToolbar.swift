import Foundation
import SwiftUI

#if os(macOS)
import AppKit
import UniformTypeIdentifiers

public struct MeetingDetailToolbar: ToolbarContent {
    private let meetingID: UUID
    private let composition: MeetingsComposition
    private let onDeleted: (() -> Void)?
    private let helperControl: (any MeetingHelperControlling)?

    public init(
        meetingID: UUID,
        composition: MeetingsComposition,
        onDeleted: (() -> Void)? = nil,
        helperControl: (any MeetingHelperControlling)? = nil
    ) {
        self.meetingID = meetingID
        self.composition = composition
        self.onDeleted = onDeleted
        self.helperControl = helperControl
    }

    public var body: some ToolbarContent {
        ToolbarItem {
            Menu {
                Button("Re-process", action: reprocess)
                if helperControl != nil, isProcessing {
                    Button("Cancel processing", action: cancelProcessing)
                }
                Button("Export as Markdown", action: exportMarkdown)
                Button("Export as JSON", action: exportJSON)
                Divider()
                Button("Delete", role: .destructive, action: delete)
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    private var isProcessing: Bool {
        guard let status = try? composition.meetingRepository.find(id: meetingID)?.processingStatus else {
            return false
        }
        switch MeetingProcessingStatus(rawValue: status) {
        case .queued, .processingVAD, .processingASR, .processingDiarization,
            .processingMerge, .processingSummary, .processingActions:
            return true
        default:
            return false
        }
    }

    private func cancelProcessing() {
        helperControl?.cancelProcessing(meetingID: meetingID)
    }

    private func reprocess() {
        guard let meeting = try? composition.meetingRepository.find(id: meetingID),
            let storage = try? composition.audioStorageRepository.find(meetingID: meetingID)
        else { return }

        let folder = storage.folderURL
        Task { @MainActor [composition, meeting, folder] in
            await composition.pipelineQueue.enqueue {
                try? await composition.pipeline.process(meeting: meeting, audioFolder: folder)
            }
        }
    }

    private func exportMarkdown() {
        guard let meeting = try? composition.meetingRepository.find(id: meetingID),
            let url = saveURL(defaultFilename: "\(filenameStem(for: meeting)).md", contentType: .plainText)
        else { return }

        let content = """
            # \(meeting.title)

            - Started: \(meeting.startedAt.formatted(date: .abbreviated, time: .shortened))
            - Duration: \(formatDuration(meeting.durationSec))

            ## Summary

            \(meeting.summaryText)

            ## Transcript

            \(meeting.transcriptText)
            """

        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func exportJSON() {
        guard let meeting = try? composition.meetingRepository.find(id: meetingID),
            let url = saveURL(defaultFilename: "\(filenameStem(for: meeting)).json", contentType: .json)
        else { return }

        let payload: [String: Any] = [
            "id": meeting.id.uuidString,
            "title": meeting.title,
            "startedAt": ISO8601DateFormatter().string(from: meeting.startedAt),
            "durationSec": meeting.durationSec,
            "summary": meeting.summaryText,
            "transcript": meeting.transcriptText,
        ]

        guard
            let data = try? JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
        else { return }

        try? data.write(to: url, options: [.atomic])
    }

    private func delete() {
        do {
            try composition.meetingRepository.delete(id: meetingID)
            onDeleted?()
        } catch {
            return
        }
    }

    private func saveURL(defaultFilename: String, contentType: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultFilename
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func filenameStem(for meeting: Meeting) -> String {
        let illegalCharacters = CharacterSet(charactersIn: "/\\:\n\r\t")
            .union(.controlCharacters)
        let sanitized = meeting.title
            .components(separatedBy: illegalCharacters)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = sanitized.isEmpty ? "Meeting-\(meeting.id.uuidString.prefix(8))" : sanitized
        return String(fallback.prefix(80))
    }

    private func formatDuration(_ durationSec: Int) -> String {
        let seconds = max(0, durationSec)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60

        guard hours > 0 else {
            return String(format: "%02d:%02d", minutes, remainingSeconds)
        }

        return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
    }
}
#endif
