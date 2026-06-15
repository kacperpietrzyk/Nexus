import Foundation

extension Notification.Name {
    /// Posted by `GraphOpenRequest.request()`. A mounted `NotesListView` reacts
    /// live; an unmounted one consumes the pending flag on appear.
    public static let notesOpenGraph = Notification.Name("notes.openGraph")
}

/// Cross-layer handoff for "open the graph view": app chrome fires the request
/// from outside the Notes surface; `NotesListView` consumes it whenever it is,
/// or becomes, mounted. Mirrors `DailyNoteOpenRequest`.
@MainActor
public final class GraphOpenRequest {
    public static let shared = GraphOpenRequest()

    public private(set) var isPending = false

    /// Internal: production uses `shared`; tests build their own instance.
    init() {}

    /// Mark a pending open and notify a mounted Notes surface.
    public func request(center: NotificationCenter = .default) {
        isPending = true
        center.post(name: .notesOpenGraph, object: nil)
    }

    /// Returns whether an open was pending, clearing it.
    public func consume() -> Bool {
        defer { isPending = false }
        return isPending
    }
}
