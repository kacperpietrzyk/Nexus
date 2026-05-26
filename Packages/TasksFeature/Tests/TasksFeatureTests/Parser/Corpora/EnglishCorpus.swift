import Foundation
import NexusCore

@testable import TasksFeature

internal enum EnglishCorpus {
    /// Anchor `now` for the entire corpus: 2026-05-04 12:00 UTC (Monday).
    static let now: Date = ISO8601DateFormatter.fixedNoon.date(from: "2026-05-04T12:00:00Z")!

    static let fixtures: [ParserFixture] = [
        // === Relative days ===
        .init(
            input: "buy milk tomorrow", expectedTitle: "buy milk",
            expectedDueAt: "2026-05-05T00:00:00Z", expectedStartAt: nil,
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "call mom today", expectedTitle: "call mom",
            expectedDueAt: "2026-05-04T00:00:00Z", expectedStartAt: nil,
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "ship review tmrw", expectedTitle: "ship review",
            expectedDueAt: "2026-05-05T00:00:00Z", expectedStartAt: nil,
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),

        // === Weekday names ===
        .init(
            input: "review friday", expectedTitle: "review",
            expectedDueAt: "2026-05-08T00:00:00Z", expectedStartAt: nil,
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "standup wed", expectedTitle: "standup",
            expectedDueAt: "2026-05-06T00:00:00Z", expectedStartAt: nil,
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "demo tuesday", expectedTitle: "demo",
            expectedDueAt: "2026-05-05T00:00:00Z", expectedStartAt: nil,
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "retro thursday", expectedTitle: "retro",
            expectedDueAt: "2026-05-07T00:00:00Z", expectedStartAt: nil,
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "groceries saturday", expectedTitle: "groceries",
            expectedDueAt: "2026-05-09T00:00:00Z", expectedStartAt: nil,
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),

        // === ISO date / DD.MM(.YYYY) ===
        .init(
            input: "deadline 2026-05-15", expectedTitle: "deadline",
            expectedDueAt: nil, expectedStartAt: nil, expectedDeadlineAt: "2026-05-15T00:00:00Z",
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "appointment 15.05.2026", expectedTitle: "appointment",
            expectedDueAt: "2026-05-15T00:00:00Z", expectedStartAt: nil,
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "vet 10.06", expectedTitle: "vet",
            expectedDueAt: "2026-06-10T00:00:00Z", expectedStartAt: nil,
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),

        // === Time-of-day ===
        .init(
            input: "alarm tomorrow morning", expectedTitle: "alarm",
            expectedDueAt: "2026-05-05T00:00:00Z", expectedStartAt: "2026-05-05T09:00:00Z",
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "workout evening", expectedTitle: "workout",
            expectedDueAt: nil, expectedStartAt: "2026-05-04T19:00:00Z",
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "meeting tomorrow 15:00", expectedTitle: "meeting",
            expectedDueAt: "2026-05-05T00:00:00Z", expectedStartAt: "2026-05-05T15:00:00Z",
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "lunch noon", expectedTitle: "lunch",
            expectedDueAt: nil, expectedStartAt: "2026-05-04T12:00:00Z",
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),

        // === Relative phrases ===
        .init(
            input: "follow up in 3 days", expectedTitle: "follow up",
            expectedDueAt: "2026-05-07T00:00:00Z", expectedStartAt: nil,
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "review in 1 week", expectedTitle: "review",
            expectedDueAt: "2026-05-11T00:00:00Z", expectedStartAt: nil,
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "renewal in 2 weeks", expectedTitle: "renewal",
            expectedDueAt: "2026-05-18T00:00:00Z", expectedStartAt: nil,
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "vacation in 3 months", expectedTitle: "vacation",
            expectedDueAt: "2026-08-02T00:00:00Z", expectedStartAt: nil,
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),

        // === Priority ===
        .init(
            input: "ship feature !1", expectedTitle: "ship feature",
            expectedDueAt: nil, expectedStartAt: nil,
            expectedPriority: .high, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "review !2", expectedTitle: "review",
            expectedDueAt: nil, expectedStartAt: nil,
            expectedPriority: .medium, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "polish !3", expectedTitle: "polish",
            expectedDueAt: nil, expectedStartAt: nil,
            expectedPriority: .low, expectedTags: [], expectedRecurrence: nil),

        // === Tags ===
        .init(
            input: "answer email #email", expectedTitle: "answer email",
            expectedDueAt: nil, expectedStartAt: nil,
            expectedPriority: nil, expectedTags: ["email"], expectedRecurrence: nil),
        .init(
            input: "kickoff #work #q3", expectedTitle: "kickoff",
            expectedDueAt: nil, expectedStartAt: nil,
            expectedPriority: nil, expectedTags: ["work", "q3"], expectedRecurrence: nil),
        // TODO: Tokenizer lowercases all tag bodies — "work/projectA" becomes "work/projecta".
        // expectedTags reflects actual parser output; desired future behavior is case-preservation.
        .init(
            input: "ship #work/projectA", expectedTitle: "ship",
            expectedDueAt: nil, expectedStartAt: nil,
            expectedPriority: nil, expectedTags: ["work/projecta"], expectedRecurrence: nil),
        .init(
            input: "task #Email", expectedTitle: "task",
            expectedDueAt: nil, expectedStartAt: nil,
            expectedPriority: nil, expectedTags: ["email"], expectedRecurrence: nil),

        // === Recurrence ===
        .init(
            input: "standup every monday", expectedTitle: "standup",
            expectedDueAt: nil, expectedStartAt: nil,
            expectedPriority: nil, expectedTags: [], expectedRecurrence: "FREQ=WEEKLY;BYDAY=MO"),
        .init(
            input: "trash every thursday", expectedTitle: "trash",
            expectedDueAt: nil, expectedStartAt: nil,
            expectedPriority: nil, expectedTags: [], expectedRecurrence: "FREQ=WEEKLY;BYDAY=TH"),
        .init(
            input: "water plants daily", expectedTitle: "water plants",
            expectedDueAt: nil, expectedStartAt: nil,
            expectedPriority: nil, expectedTags: [], expectedRecurrence: "FREQ=DAILY"),
        .init(
            input: "rent monthly", expectedTitle: "rent",
            expectedDueAt: nil, expectedStartAt: nil,
            expectedPriority: nil, expectedTags: [], expectedRecurrence: "FREQ=MONTHLY"),
        .init(
            input: "weekly review", expectedTitle: "review",
            expectedDueAt: nil, expectedStartAt: nil,
            expectedPriority: nil, expectedTags: [], expectedRecurrence: "FREQ=WEEKLY"),
        .init(
            input: "standup every monday 09:00", expectedTitle: "standup",
            expectedDueAt: nil, expectedStartAt: "2026-05-04T09:00:00Z",
            expectedPriority: nil, expectedTags: [], expectedRecurrence: "FREQ=WEEKLY;BYDAY=MO"),

        // === Combinations ===
        .init(
            input: "buy milk tomorrow 15:00 !2 #shopping", expectedTitle: "buy milk",
            expectedDueAt: "2026-05-05T00:00:00Z", expectedStartAt: "2026-05-05T15:00:00Z",
            expectedPriority: .medium, expectedTags: ["shopping"], expectedRecurrence: nil),
        .init(
            input: "ship review friday !1 #work", expectedTitle: "ship review",
            expectedDueAt: "2026-05-08T00:00:00Z", expectedStartAt: nil,
            expectedPriority: .high, expectedTags: ["work"], expectedRecurrence: nil),
        .init(
            input: "report weekly !2 #team", expectedTitle: "report",
            expectedDueAt: nil, expectedStartAt: nil,
            expectedPriority: .medium, expectedTags: ["team"], expectedRecurrence: "FREQ=WEEKLY"),

        // === Title-only (low confidence — handcoded should still produce title) ===
        .init(
            input: "buy bread", expectedTitle: "buy bread",
            expectedDueAt: nil, expectedStartAt: nil,
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "fix garage", expectedTitle: "fix garage",
            expectedDueAt: nil, expectedStartAt: nil,
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),

        // === Edge cases the corpus expects to TOLERATE missing (FM picks them up later) ===
        .init(
            input: "after lunch call mom", expectedTitle: "after lunch call mom",
            expectedDueAt: nil, expectedStartAt: nil,
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "sometime next week", expectedTitle: "sometime next week",
            expectedDueAt: nil, expectedStartAt: nil,
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),

        // === More straightforward fixtures ===
        .init(
            input: "submit report tomorrow", expectedTitle: "submit report",
            expectedDueAt: "2026-05-05T00:00:00Z", expectedStartAt: nil,
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "yoga today morning", expectedTitle: "yoga",
            expectedDueAt: "2026-05-04T00:00:00Z", expectedStartAt: "2026-05-04T09:00:00Z",
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
        // "pojutrze" is not in EnglishPhrases.relativeDays — falls through as residual.
        // Title joins residuals; dueAt nil; startAt anchored to today's 14:30.
        .init(
            input: "doctor visit pojutrze 14:30", expectedTitle: "doctor visit pojutrze",
            expectedDueAt: nil, expectedStartAt: "2026-05-04T14:30:00Z",
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "deadline 31.12", expectedTitle: "deadline",
            expectedDueAt: nil, expectedStartAt: nil, expectedDeadlineAt: "2026-12-31T00:00:00Z",
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "meeting 2026-06-15 10:00", expectedTitle: "meeting",
            expectedDueAt: "2026-06-15T00:00:00Z", expectedStartAt: "2026-06-15T10:00:00Z",
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "release sun !2", expectedTitle: "release",
            expectedDueAt: "2026-05-10T00:00:00Z", expectedStartAt: nil,
            expectedPriority: .medium, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "exercise daily morning", expectedTitle: "exercise",
            expectedDueAt: nil, expectedStartAt: "2026-05-04T09:00:00Z",
            expectedPriority: nil, expectedTags: [], expectedRecurrence: "FREQ=DAILY"),
        .init(
            input: "1on1 every tuesday 16:00", expectedTitle: "1on1",
            expectedDueAt: nil, expectedStartAt: "2026-05-04T16:00:00Z",
            expectedPriority: nil, expectedTags: [], expectedRecurrence: "FREQ=WEEKLY;BYDAY=TU"),
        .init(
            input: "review #work tomorrow", expectedTitle: "review",
            expectedDueAt: "2026-05-05T00:00:00Z", expectedStartAt: nil,
            expectedPriority: nil, expectedTags: ["work"], expectedRecurrence: nil),
        .init(
            input: "vacation plan 15.07.2026", expectedTitle: "vacation plan",
            expectedDueAt: "2026-07-15T00:00:00Z", expectedStartAt: nil,
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "cleaning saturday morning !3", expectedTitle: "cleaning",
            expectedDueAt: "2026-05-09T00:00:00Z", expectedStartAt: "2026-05-09T09:00:00Z",
            expectedPriority: .low, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "trip in 5 days", expectedTitle: "trip",
            expectedDueAt: "2026-05-09T00:00:00Z", expectedStartAt: nil,
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "ship deadline 20.05 !1", expectedTitle: "ship",
            expectedDueAt: nil, expectedStartAt: nil, expectedDeadlineAt: "2026-05-20T00:00:00Z",
            expectedPriority: .high, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "submit report deadline tomorrow", expectedTitle: "submit report",
            expectedDueAt: nil, expectedStartAt: nil, expectedDeadlineAt: "2026-05-05T00:00:00Z",
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "audit report deadline 2026-05-01", expectedTitle: "audit report",
            expectedDueAt: nil, expectedStartAt: nil, expectedDeadlineAt: "2026-05-01T00:00:00Z",
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "file taxes by friday", expectedTitle: "file taxes",
            expectedDueAt: nil, expectedStartAt: nil, expectedDeadlineAt: "2026-05-08T00:00:00Z",
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "send deck due by 2026-05-15", expectedTitle: "send deck",
            expectedDueAt: nil, expectedStartAt: nil, expectedDeadlineAt: "2026-05-15T00:00:00Z",
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "renew passport no later than 20.05", expectedTitle: "renew passport",
            expectedDueAt: nil, expectedStartAt: nil, expectedDeadlineAt: "2026-05-20T00:00:00Z",
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "meeting tomorrow by friday", expectedTitle: "meeting",
            expectedDueAt: "2026-05-05T00:00:00Z", expectedStartAt: nil, expectedDeadlineAt: "2026-05-08T00:00:00Z",
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "call supplier by tomorrow 17:00", expectedTitle: "call supplier",
            expectedDueAt: nil, expectedStartAt: nil, expectedDeadlineAt: "2026-05-05T17:00:00Z",
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
        .init(
            input: "1:1 #lead wednesday 14:00", expectedTitle: "1:1",
            expectedDueAt: "2026-05-06T00:00:00Z", expectedStartAt: "2026-05-06T14:00:00Z",
            expectedPriority: nil, expectedTags: ["lead"], expectedRecurrence: nil),
        .init(
            input: "earn more sometime", expectedTitle: "earn more sometime",
            expectedDueAt: nil, expectedStartAt: nil,
            expectedPriority: nil, expectedTags: [], expectedRecurrence: nil),
    ]
}
