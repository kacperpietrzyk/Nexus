import Foundation
import SwiftData

/// "Today's note, one action away" (gap-matrix O4): idempotent open-or-create
/// of the daily note for a given day, plus prev/next lookup between EXISTING
/// daily notes for date navigation.
///
/// Identity: `role == .dailyNote` + the `DailyNoteConvention` title — the SAME
/// convention `AgentBriefDailyNoteWriter` (NexusAgent) uses, so the user's
/// "Today" action and the agent's brief upsert share one note per day.
///
/// Fetches mirror the agent's lookup: `#Predicate` on `deletedAt == nil` only,
/// `role` filtered in Swift (enum stored fields don't filter reliably in
/// `#Predicate` — the documented `NoteReconciler` rule).
@MainActor
public struct DailyNoteService {
    public enum Direction {
        case previous
        case next
    }

    public let repository: NoteRepository
    public let calendar: Calendar

    public init(repository: NoteRepository, calendar: Calendar = .current) {
        self.repository = repository
        self.calendar = calendar
    }

    /// The existing daily note for the day containing `date`, if any.
    public func existingDailyNote(for date: Date) throws -> Note? {
        let title = DailyNoteConvention.title(for: date, calendar: calendar)
        return try liveDailyNotes().first { $0.title == title }
    }

    /// Idempotent: returns the existing daily note for the day containing
    /// `date` (whether the user or the agent created it), else creates an empty
    /// one with the deterministic convention title/tags and `role == .dailyNote`.
    @discardableResult
    public func openOrCreate(for date: Date) throws -> Note {
        if let existing = try existingDailyNote(for: date) {
            return existing
        }
        return try repository.create(
            title: DailyNoteConvention.title(for: date, calendar: calendar),
            blocks: [],
            role: .dailyNote,
            tags: DailyNoteConvention.tags(for: date, calendar: calendar)
        )
    }

    /// The day (start-of-day) a daily note represents, decoded from its title.
    /// `nil` for non-daily notes or titles outside the convention.
    public func day(of note: Note) -> Date? {
        guard note.role == .dailyNote else { return nil }
        return DailyNoteConvention.date(fromTitle: note.title, calendar: calendar)
    }

    /// The nearest EXISTING daily note strictly before/after `note`'s day.
    /// Skips gaps (e.g. a missing weekend); `nil` at the edges or when `note`
    /// itself has no decodable day.
    public func adjacentDailyNote(from note: Note, direction: Direction) throws -> Note? {
        guard let anchor = day(of: note) else { return nil }
        let dated: [(day: Date, note: Note)] = try liveDailyNotes().compactMap { candidate in
            guard let candidateDay = day(of: candidate) else { return nil }
            return (candidateDay, candidate)
        }
        switch direction {
        case .previous:
            return dated.filter { $0.day < anchor }.max { $0.day < $1.day }?.note
        case .next:
            return dated.filter { $0.day > anchor }.min { $0.day < $1.day }?.note
        }
    }

    private func liveDailyNotes() throws -> [Note] {
        try repository.context
            .fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.deletedAt == nil }))
            .filter { $0.role == .dailyNote }
    }
}
