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

    static func addResult(draft: String, save: (String) throws -> Void) -> CommentsComposerResult {
        guard let body = sanitized(draft) else {
            return CommentsComposerResult(draft: draft, errorMessage: nil, shouldReload: false)
        }
        do {
            try save(body)
            return CommentsComposerResult(draft: "", errorMessage: nil, shouldReload: true)
        } catch {
            return CommentsComposerResult(
                draft: draft,
                errorMessage: "Could not add comment.",
                shouldReload: false
            )
        }
    }
}

struct CommentsComposerResult: Equatable {
    let draft: String
    let errorMessage: String?
    let shouldReload: Bool
}

enum CommentsLoader {
    static func reloadResult(existing: [Comment], load: () throws -> [Comment]) -> CommentsReloadResult {
        do {
            return CommentsReloadResult(comments: try load(), errorMessage: nil)
        } catch {
            return CommentsReloadResult(comments: existing, errorMessage: "Could not load comments.")
        }
    }
}

struct CommentsReloadResult {
    let comments: [Comment]
    let errorMessage: String?
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
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !comments.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(comments, id: \.id) { comment in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(comment.body)
                                .font(DS.FontToken.body)
                                .foregroundStyle(DS.ColorToken.textPrimary)
                            Text(
                                comment.createdAt.formatted(
                                    date: .abbreviated,
                                    time: .shortened
                                )
                            )
                            .font(DS.FontToken.metadata)
                            .foregroundStyle(DS.ColorToken.textTertiary)
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

            if let errorMessage {
                Text(errorMessage)
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textPrimary)
            }
        }
        // Reload when item identity changes (inspector reuses the view across
        // task-selection swaps; `.onAppear` would not re-fire in that case).
        .task(id: itemID) {
            comments = []
            errorMessage = nil
            reload()
        }
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
        let result = CommentsLoader.reloadResult(existing: comments) {
            try repository.comments(for: itemID, kind: itemKind)
        }
        comments = result.comments
        errorMessage = result.errorMessage
    }

    private func add() {
        let result = CommentsComposer.addResult(draft: draft) { body in
            _ = try repository.add(body: body, to: itemID, kind: itemKind)
        }
        draft = result.draft
        errorMessage = result.errorMessage
        if result.shouldReload {
            reload()
        }
    }
}
