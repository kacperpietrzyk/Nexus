import Foundation
import NexusUI
import SwiftData

public final class AgentThreadStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    public func create(
        title: String,
        projectID: UUID? = nil,
        modelHint: String? = nil
    ) throws -> UUID {
        let thread = AgentThread(title: title, projectID: projectID, modelHint: modelHint)
        context.insert(thread)
        try context.save()
        return thread.id
    }

    public func get(id: UUID) throws -> AgentThread? {
        try context.fetch(
            FetchDescriptor<AgentThread>(
                predicate: #Predicate { $0.id == id }
            )
        ).first
    }

    public func allActive() throws -> [AgentThread] {
        try context.fetch(
            FetchDescriptor<AgentThread>(
                predicate: #Predicate { $0.archivedAt == nil },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse), SortDescriptor(\.id, order: .reverse)]
            )
        )
    }

    public func allArchived() throws -> [AgentThread] {
        try context.fetch(
            FetchDescriptor<AgentThread>(
                predicate: #Predicate { $0.archivedAt != nil },
                sortBy: [SortDescriptor(\.archivedAt, order: .reverse), SortDescriptor(\.id, order: .reverse)]
            )
        )
    }

    public func archive(id: UUID, now: Date = .now) throws {
        guard let thread = try get(id: id) else { return }
        thread.archivedAt = now
        thread.updatedAt = now
        try context.save()
    }

    public func touch(id: UUID, now: Date = .now) throws {
        guard let thread = try get(id: id) else { return }
        thread.updatedAt = now
        try context.save()
    }

    /// Restores an archived thread (clears `archivedAt`). No-op if the thread
    /// is not found or is already active.
    public func unarchive(id: UUID, now: Date = .now) throws {
        guard let thread = try get(id: id) else { return }
        thread.archivedAt = nil
        thread.updatedAt = now
        try context.save()
    }

    /// Renames the thread, trimming whitespace. A blank title becomes "Untitled".
    public func rename(id: UUID, title: String, now: Date = .now) throws {
        guard let thread = try get(id: id) else { return }
        thread.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        thread.updatedAt = now
        try context.save()
    }

    /// Pins or unpins a thread. Pinned threads sort above unpinned ones in the rail.
    /// Toggling: if already pinned, clears `pinnedAt`; otherwise stamps it.
    public func togglePin(id: UUID, now: Date = .now) throws {
        guard let thread = try get(id: id) else { return }
        thread.pinnedAt = thread.pinnedAt == nil ? now : nil
        thread.updatedAt = now
        try context.save()
    }

    /// Hard-deletes the thread record. Messages are NOT cascade-deleted here —
    /// the caller is responsible for pruning orphaned messages if needed. Use only
    /// for explicit "Delete conversation" actions (not archive).
    public func delete(id: UUID) throws {
        guard let thread = try get(id: id) else { return }
        context.delete(thread)
        try context.save()
    }

    /// Markdown export of a thread's title + recent messages (up to `limit` messages).
    /// Delegates message loading to `messageStore`; the output is a canonical
    /// `MarkdownExport.entity` block with one checklist line per message.
    public func exportMarkdown(
        id: UUID,
        messageStore: AgentMessageStore,
        limit: Int = 200
    ) throws -> String {
        guard let thread = try get(id: id) else { return "" }
        let messages = (try? messageStore.slidingWindow(threadID: id, last: limit)) ?? []
        let lines: [String] = messages.compactMap { msg in
            guard msg.role == .user || msg.role == .agent else { return nil }
            let role = msg.role == .user ? "You" : "Nexus"
            let body = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return nil }
            return "**\(role):** \(body)"
        }
        let displayTitle = thread.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let heading = displayTitle.isEmpty ? "Untitled Thread" : displayTitle
        return MarkdownExport.entity(title: heading, body: lines.joined(separator: "\n\n"))
    }
}
