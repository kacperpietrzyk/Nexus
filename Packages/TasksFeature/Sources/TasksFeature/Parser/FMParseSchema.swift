import Foundation

/// JSON-contract DTO consumed by `FoundationModelParser`. The shape mirrors
/// `ParseResult` but uses primitives that can survive a free-form LM round
/// trip — `dueAt` / `startAt` / `endAt` are ISO8601 strings so partial dates can be
/// rejected at decode time, and `priority` is an Int rather than the typed
/// `TaskPriority` (LM occasionally emits 0 / 4 / null inconsistently).
internal struct FMParseSchema: Decodable, Sendable, Equatable {
    let title: String
    let dueAt: String?
    let startAt: String?
    let endAt: String?
    let deadlineAt: String?
    let priority: Int?
    let tags: [String]?
    let project: String?
    let recurrence: String?
}
