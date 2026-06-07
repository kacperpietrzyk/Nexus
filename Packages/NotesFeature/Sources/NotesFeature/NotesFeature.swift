/// NotesFeature — the native UI for the Notes content layer (spec §5).
///
/// Public surface:
/// - ``NotesListView`` — the notes list + new-note affordance (mountable in app nav).
/// - ``NotesComposition`` — builds the production ``NexusCore/NoteRepository``.
/// - `\.noteRepository` environment key — inject the repository from the app root.
///
/// Depends only on `NexusCore` (+ `NexusUI` design tokens). It never imports
/// `TasksFeature`; the checkbox→Task seam lives in `NexusCore`'s `NoteReconciler` /
/// `NoteRepository` (spec §3). macOS + iOS only — the Watch projection is a bespoke
/// read-only view in the Watch app target.
public enum NotesFeature {}
