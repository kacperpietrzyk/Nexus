import Combine
import Foundation
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
                Text("Summary")
                    .font(.headline)
                Spacer()
                if !isReadOnly {
                    Toggle("Edit", isOn: editingBinding)
                        .toggleStyle(.button)
                }
            }

            if let saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if viewModel.editing {
                TextEditor(text: $viewModel.rawMarkdown)
                    .font(.body.monospaced())
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(.init(viewModel.rawMarkdown))
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
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
