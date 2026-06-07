import NexusCore
import NexusUI
import SwiftUI

/// Pure text-sanitisation for the comment composer. Kept separate so it is
/// testable without SwiftUI.
enum CommentsComposer {
    /// Returns a trimmed body, or `nil` when empty/whitespace-only.
    static func sanitized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Reusable comment thread for any item (task or project). Loads via the
/// repository when `itemID` changes and after each mutation. Renders chrome-
/// less inside an `inspectorCard` host — it does not supply its own card.
struct CommentsSection: View {
    let itemID: UUID
    let itemKind: ItemKind
    let repository: CommentRepository

    @State private var comments: [Comment] = []
    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !comments.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(comments, id: \.id) { comment in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(comment.body)
                                .font(NexusType.body)
                                .foregroundStyle(NexusColor.Text.primary)
                            Text(
                                comment.createdAt.formatted(
                                    date: .abbreviated,
                                    time: .shortened
                                )
                            )
                            .font(NexusType.caption)
                            .foregroundStyle(NexusColor.Text.tertiary)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                draftField
                NexusButton(
                    variant: .outline,
                    size: .sm,
                    action: { add() },
                    label: { Text("Add") }
                )
                .disabled(CommentsComposer.sanitized(draft) == nil)
            }
        }
        // Reload when item identity changes (inspector reuses the view across
        // task-selection swaps; `.onAppear` would not re-fire in that case).
        .task(id: itemID) { reload() }
    }

    @ViewBuilder
    private var draftField: some View {
        #if os(iOS)
        TextField("Add a comment", text: $draft)
            .textInputAutocapitalization(.sentences)
        #else
        TextField("Add a comment", text: $draft)
        #endif
    }

    private func reload() {
        comments = (try? repository.comments(for: itemID, kind: itemKind)) ?? []
    }

    private func add() {
        guard let body = CommentsComposer.sanitized(draft) else { return }
        try? repository.add(body: body, to: itemID, kind: itemKind)
        draft = ""
        reload()
    }
}
