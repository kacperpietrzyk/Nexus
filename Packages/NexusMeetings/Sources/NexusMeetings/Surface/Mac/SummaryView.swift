import Combine
import Foundation
import NexusUI
import SwiftData
import SwiftUI

@MainActor
public final class SummaryViewModel: ObservableObject {
    @Published public var rawMarkdown: String = ""
    @Published public var editing: Bool = false

    private let meetingID: UUID
    private let repository: MeetingRepository
    private var hasLoaded = false

    public init(meetingID: UUID, repository: MeetingRepository) {
        self.meetingID = meetingID
        self.repository = repository
    }

    public func load(force: Bool = false) {
        guard !editing, force || !hasLoaded else { return }
        rawMarkdown = (try? repository.find(id: meetingID))?.summaryText ?? ""
        hasLoaded = true
    }

    public func save() throws {
        guard let meeting = try repository.find(id: meetingID) else { return }
        meeting.summaryText = rawMarkdown
        meeting.updatedAt = Date()
        try repository.upsert(meeting)
    }
}

public struct SummaryView: View {
    @StateObject private var viewModel: SummaryViewModel
    private let isReadOnly: Bool
    @State private var saveError: String?

    public init(
        meetingID: UUID,
        repository: MeetingRepository,
        isReadOnly: Bool = false
    ) {
        self.isReadOnly = isReadOnly
        _viewModel = StateObject(
            wrappedValue: SummaryViewModel(meetingID: meetingID, repository: repository)
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SUMMARY")
                    .nexusType(.eyebrow)
                    .foregroundStyle(NexusColor.Text.muted)
                Spacer()
                if !isReadOnly {
                    Toggle("Edit", isOn: editingBinding)
                        .toggleStyle(.button)
                        .font(NexusType.meta)
                }
            }

            if let saveError {
                Text(saveError)
                    .font(NexusType.meta)
                    .foregroundStyle(NexusColor.Status.danger)
            }

            if viewModel.editing {
                TextEditor(text: $viewModel.rawMarkdown)
                    .font(NexusType.bodySmall.monospaced())
                    .foregroundStyle(NexusColor.Text.secondary)
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    MeetingSummaryMarkdown(raw: viewModel.rawMarkdown)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            viewModel.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            viewModel.load(force: true)
        }
    }

    private var editingBinding: Binding<Bool> {
        Binding(
            get: { viewModel.editing },
            set: { nextValue in
                let wasEditing = viewModel.editing
                viewModel.editing = nextValue
                guard wasEditing, !nextValue else { return }

                do {
                    try viewModel.save()
                    saveError = nil
                } catch {
                    saveError = error.localizedDescription
                    viewModel.editing = true
                }
            }
        )
    }
}

/// Lightweight block-markdown renderer for the meeting summary. SwiftUI's
/// `Text(.init(markdown:))` parses only INLINE markdown (bold/italic), so raw
/// `##` headings and `-` bullets render literally. This splits the source into
/// block lines and renders headings / bullets / paragraphs with Nexus tokens,
/// still delegating inline emphasis to `AttributedString` per line.
private struct MeetingSummaryMarkdown: View {
    let raw: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                row(for: block)
            }
        }
        .textSelection(.enabled)
        .tint(NexusColor.Text.primary)
    }

    @ViewBuilder
    private func row(for block: Block) -> some View {
        switch block {
        case .heading(let text):
            Text(inline(text))
                .font(NexusType.h3)
                .foregroundStyle(NexusColor.Text.primary)
                .padding(.top, 4)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(NexusType.body)
                    .foregroundStyle(NexusColor.Text.muted)
                Text(inline(text))
                    .font(NexusType.body)
                    .foregroundStyle(NexusColor.Text.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .numbered(let index, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(index).")
                    .font(NexusType.body)
                    .monospacedDigit()
                    .foregroundStyle(NexusColor.Text.muted)
                Text(inline(text))
                    .font(NexusType.body)
                    .foregroundStyle(NexusColor.Text.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .paragraph(let text):
            Text(inline(text))
                .font(NexusType.body)
                .foregroundStyle(NexusColor.Text.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    private enum Block {
        case heading(String)
        case bullet(String)
        case numbered(index: Int, text: String)
        case paragraph(String)
    }

    private var blocks: [Block] {
        raw.split(separator: "\n", omittingEmptySubsequences: true).map { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let hash = line.range(of: "^#{1,6}\\s+", options: .regularExpression) {
                return .heading(String(line[hash.upperBound...]))
            }
            if let bullet = line.range(of: "^[-*]\\s+", options: .regularExpression) {
                return .bullet(String(line[bullet.upperBound...]))
            }
            if let marker = line.range(of: "^\\d+\\.\\s+", options: .regularExpression) {
                let digits = line[marker.lowerBound..<line.index(before: marker.upperBound)]
                    .prefix { $0.isNumber }
                let index = Int(digits) ?? 0
                return .numbered(index: index, text: String(line[marker.upperBound...]))
            }
            return .paragraph(line)
        }
    }
}
