import Foundation

extension Notification.Name {
    /// Posted by `DailyNoteOpenRequest.request()`. A mounted `NotesListView`
    /// reacts live; an unmounted one consumes the pending flag on appear.
    public static let notesOpenDailyNote = Notification.Name("notes.openDailyNote")
}

/// Cross-layer handoff for "open today's daily note" (O4): app chrome (menu
/// item, ⌘⇧D, command palette) fires the request from OUTSIDE the Notes
/// surface; `NotesListView` consumes it whenever it is — or becomes — mounted.
///
/// Two delivery paths cover both mount states:
/// - already mounted → the `.notesOpenDailyNote` notification is received live;
/// - not mounted yet → the caller navigates to Notes and the list consumes the
///   pending flag in its `.task` on appear.
/// `consume()` clears the flag, so double delivery collapses to one open.
@MainActor
public final class DailyNoteOpenRequest {
    public static let shared = DailyNoteOpenRequest()

    public private(set) var isPending = false

    /// Internal: production uses `shared`; tests build their own instance.
    init() {}

    /// Mark a pending open and notify a mounted Notes surface.
    public func request(center: NotificationCenter = .default) {
        isPending = true
        center.post(name: .notesOpenDailyNote, object: nil)
    }

    /// Returns whether an open was pending, clearing it (one open per request).
    public func consume() -> Bool {
        defer { isPending = false }
        return isPending
    }
}
