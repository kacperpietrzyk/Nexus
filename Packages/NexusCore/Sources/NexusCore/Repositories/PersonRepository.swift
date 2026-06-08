import Foundation
import SwiftData

/// The endpoint a `Person` can be linked FROM (People/Contacts module, spec §4.2).
/// A meeting links a person as an attendee; a task or note mentions a person. A
/// `Person` is NEVER an assignee — `task ↔ person` is exclusively `.mentions`
/// (invariant I1, spec §5).
public enum PersonSourceKind: Sendable {
    case meeting
    case task
    case note

    var itemKind: ItemKind {
        switch self {
        case .meeting: return .meeting
        case .task: return .task
        case .note: return .note
        }
    }

    /// The single edge label this source uses to point at a `Person`. Meetings use
    /// `.attendee`; tasks and notes use `.mentions` (never ownership — I1).
    var linkKind: LinkKind {
        switch self {
        case .meeting: return .attendee
        case .task, .note: return .mentions
        }
    }
}

/// A grouped, graph-resolved view of "everything about a person" (spec §7 aggregation).
/// Each member is a raw graph endpoint `(ItemKind, UUID)` — `PersonRepository` cannot
/// resolve the concrete `Meeting`/`TaskItem`/`Note` (cross-package); callers fetch the
/// rows in their own module. Derived purely from reverse-querying the `Link` graph.
public struct PersonAggregate: Sendable, Equatable {
    /// Meetings the person attended (`.attendee` edges, `fromKind == .meeting`).
    public var meetings: [UUID]
    /// Tasks that mention the person (`.mentions` edges, `fromKind == .task`).
    public var tasks: [UUID]
    /// Notes that mention the person (`.mentions` edges, `fromKind == .note`).
    public var notes: [UUID]

    public init(meetings: [UUID] = [], tasks: [UUID] = [], notes: [UUID] = []) {
        self.meetings = meetings
        self.tasks = tasks
        self.notes = notes
    }
}

/// CRUD + soft-delete + dedup/upsert + atomic merge + graph aggregation for `Person`
/// (People/Contacts module, spec §4.1–4.3, §5, §7). Bound to a single `ModelContext`;
/// never share across actors.
///
/// **Single-user boundary (I1):** the only `task ↔ person` / `note ↔ person` helper
/// emits `LinkKind.mentions`; there is no assignee parameter or code path that could
/// make a `Person` own a task. `meeting ↔ person` uses `.attendee`.
@MainActor
public final class PersonRepository {
    public let context: ModelContext
    public let now: () -> Date
    private let links: LinkRepository
    /// Search/Spotlight observers (mirrors `LinkableRepository`). When non-empty, the
    /// repo fires `didUpsert` after create/update/upsert (when the indexed
    /// `searchableText` — displayName + aliases + company — changes) and
    /// `didSoftDelete` after softDelete/merge. Default empty so existing callers and
    /// tests are unaffected. Graph-edge ops (`linkMention`/`linkAttendee`) don't touch
    /// `searchableText`, so they don't fan out.
    private let observers: [any LinkableObserver]

    public init(
        context: ModelContext,
        now: @escaping () -> Date = { .now },
        observers: [any LinkableObserver] = []
    ) {
        self.context = context
        self.now = now
        self.links = LinkRepository(context: context)
        self.observers = observers
    }

    /// Fans out an upsert for `person` (snapshot built on `@MainActor`, awaited into
    /// each observer's actor via detached `Task`). Mirrors `LinkableRepository`.
    private func broadcastUpsert(for person: Person) {
        guard !observers.isEmpty else { return }
        let document = IndexedDocument(person)
        for observer in observers {
            _Concurrency.Task { await observer.didUpsert(document) }
        }
    }

    /// Fans out a soft-delete for `person` to every observer.
    private func broadcastSoftDelete(for person: Person) {
        guard !observers.isEmpty else { return }
        let id = person.id
        for observer in observers {
            _Concurrency.Task { await observer.didSoftDelete(kind: .person, id: id) }
        }
    }

    // MARK: - CRUD

    @discardableResult
    public func create(
        displayName: String,
        aliases: [String] = [],
        email: String? = nil,
        phone: String? = nil,
        company: String? = nil,
        note: String? = nil,
        externalSourceID: String? = nil
    ) throws -> Person {
        let stamp = now()
        let person = Person(
            displayName: displayName,
            aliases: aliases,
            email: email,
            phone: phone,
            company: company,
            note: note,
            externalSourceID: externalSourceID
        )
        person.createdAt = stamp
        person.updatedAt = stamp
        context.insert(person)
        try context.save()
        broadcastUpsert(for: person)
        return person
    }

    public func update(
        _ person: Person,
        displayName: String? = nil,
        aliases: [String]? = nil,
        email: String?? = nil,
        phone: String?? = nil,
        company: String?? = nil,
        note: String?? = nil
    ) throws {
        if let displayName { person.displayName = displayName }
        if let aliases { person.aliases = aliases }
        if let email { person.email = email }
        if let phone { person.phone = phone }
        if let company { person.company = company }
        if let note { person.note = note }
        person.updatedAt = now()
        try context.save()
        broadcastUpsert(for: person)
    }

    public func find(id: UUID) throws -> Person? {
        let descriptor = FetchDescriptor<Person>(
            predicate: #Predicate { person in person.id == id }
        )
        return try context.fetch(descriptor).first
    }

    /// All live (non-soft-deleted) people, sorted by display name.
    public func allActive() throws -> [Person] {
        try context.fetch(FetchDescriptor<Person>())
            .filter { $0.deletedAt == nil }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Soft-deletes a person (invariant I4): stamps `deletedAt` and removes ALL graph
    /// edges incident on the person (incoming `.attendee`/`.mentions`) so that
    /// meetings/tasks/notes lose the dangling link but otherwise survive. Single
    /// terminal save.
    public func softDelete(_ person: Person) throws {
        let endpoint: (ItemKind, UUID) = (.person, person.id)
        for edge in try links.backlinks(to: endpoint) {
            context.delete(edge)
        }
        for edge in try links.outgoing(from: endpoint) {
            context.delete(edge)
        }
        let stamp = now()
        person.deletedAt = stamp
        person.updatedAt = stamp
        try context.save()
        broadcastSoftDelete(for: person)
    }

    // MARK: - Dedup / upsert (spec §4.3)

    /// Idempotent upsert keyed on `externalSourceID` (spec §4.3): the same
    /// `externalSourceID` UPDATES the existing person rather than creating a
    /// duplicate. Mutable fields are filled in only when the incoming value is
    /// non-nil/non-empty (enrichment, never clobbering with blanks); incoming
    /// aliases are unioned in.
    @discardableResult
    public func upsert(
        externalSourceID: String,
        displayName: String,
        aliases: [String] = [],
        email: String? = nil,
        phone: String? = nil,
        company: String? = nil,
        note: String? = nil
    ) throws -> Person {
        let descriptor = FetchDescriptor<Person>(
            predicate: #Predicate { person in person.externalSourceID == externalSourceID }
        )
        if let existing = try context.fetch(descriptor).first(where: { $0.deletedAt == nil }) {
            if !displayName.isEmpty { existing.displayName = displayName }
            existing.aliases = Self.mergedAliases(existing.aliases, aliases)
            if let email, !email.isEmpty { existing.email = email }
            if let phone, !phone.isEmpty { existing.phone = phone }
            if let company, !company.isEmpty { existing.company = company }
            if let note, !note.isEmpty { existing.note = note }
            existing.updatedAt = now()
            try context.save()
            broadcastUpsert(for: existing)
            return existing
        }
        return try create(
            displayName: displayName,
            aliases: aliases,
            email: email,
            phone: phone,
            company: company,
            note: note,
            externalSourceID: externalSourceID
        )
    }

    /// Soft-match for a manual add/label (spec §4.3): returns an existing live person
    /// whose `displayName` or any alias matches `query` case/diacritic-insensitively,
    /// or nil. SUGGESTS an existing person — never auto-creates or mutates.
    public func suggestExisting(matching query: String) throws -> Person? {
        let needle = Self.fold(query)
        guard !needle.isEmpty else { return nil }
        return try allActive().first { person in
            let names = [person.displayName] + person.aliases
            return names.contains { Self.fold($0) == needle }
        }
    }

    // MARK: - Merge (spec §4.3, invariant I2 — atomic)

    /// Atomically merges `from` into `into` (spec §4.3, invariant I2):
    ///
    /// 1. repoints every graph edge incident on `from` onto `into` (in-place endpoint
    ///    rewrite, de-duplicating against edges `into` already has);
    /// 2. unions `from`'s aliases (plus `from.displayName`) into `into`;
    /// 3. fills any empty `into` field (email/phone/company/note) from `from`;
    /// 4. soft-deletes `from`.
    ///
    /// All mutations run on one `ModelContext` and commit via a single terminal
    /// `context.save()` (like `ProjectPromoter`). Edge repointing mutates `Link`
    /// endpoints directly rather than routing through `LinkRepository` (whose
    /// `findOrCreate`/`delete` each save), so a throw before the terminal save leaves
    /// nothing persisted — no orphaned edge (I2). Throws (saving nothing) if `from`
    /// and `into` are the same person or `from` is already deleted.
    public func mergePeople(into: Person, from: Person) throws {
        guard into.id != from.id else {
            throw PersonMergeError.cannotMergeIntoSelf(personID: from.id)
        }
        guard from.deletedAt == nil else {
            throw PersonMergeError.sourceAlreadyDeleted(personID: from.id)
        }
        let stamp = now()
        let intoEndpoint: (ItemKind, UUID) = (.person, into.id)
        let fromEndpoint: (ItemKind, UUID) = (.person, from.id)

        // 1. Repoint edges. A Person is always the `to` endpoint, but repoint both
        //    directions defensively. De-dupe against edges already on `into`.
        var existingIncoming = Set(
            try links.backlinks(to: intoEndpoint).map { Self.edgeKey($0) }
        )
        for edge in try links.backlinks(to: fromEndpoint) {
            edge.toID = into.id
            let key = Self.edgeKey(edge)
            if existingIncoming.contains(key) {
                context.delete(edge)
            } else {
                existingIncoming.insert(key)
            }
        }
        var existingOutgoing = Set(
            try links.outgoing(from: intoEndpoint).map { Self.edgeKey($0) }
        )
        for edge in try links.outgoing(from: fromEndpoint) {
            edge.fromID = into.id
            let key = Self.edgeKey(edge)
            if existingOutgoing.contains(key) {
                context.delete(edge)
            } else {
                existingOutgoing.insert(key)
            }
        }

        // 2. Merge aliases (include from's display name as an alias).
        into.aliases = Self.mergedAliases(into.aliases, [from.displayName] + from.aliases)

        // 3. Fill empty into-fields from from.
        if (into.email ?? "").isEmpty { into.email = from.email }
        if (into.phone ?? "").isEmpty { into.phone = from.phone }
        if (into.company ?? "").isEmpty { into.company = from.company }
        if (into.note ?? "").isEmpty { into.note = from.note }
        into.updatedAt = stamp

        // 4. Soft-delete the duplicate.
        from.deletedAt = stamp
        from.updatedAt = stamp

        try context.save()

        // The survivor's searchable text changed (merged aliases / filled fields);
        // the merged-away duplicate is now a tombstone. Re-index one, evict the other.
        broadcastUpsert(for: into)
        broadcastSoftDelete(for: from)
    }

    // MARK: - Graph edges (spec §4.2)

    /// Links a meeting to a person as an attendee (`.attendee`). Idempotent.
    @discardableResult
    public func linkAttendee(meetingID: UUID, personID: UUID) throws -> Link {
        try links.findOrCreate(
            from: (.meeting, meetingID),
            to: (.person, personID),
            linkKind: .attendee
        )
    }

    /// Links a task or note to a person as a MENTION (`.mentions`) — never an
    /// assignee/owner (invariant I1). Idempotent.
    @discardableResult
    public func linkMention(source: PersonSourceKind, sourceID: UUID, personID: UUID) throws -> Link {
        try links.findOrCreate(
            from: (source.itemKind, sourceID),
            to: (.person, personID),
            linkKind: .mentions
        )
    }

    // MARK: - Aggregation (spec §7)

    /// "Everything about a person" via reverse-query over the `Link` graph (spec §7):
    /// meetings (`.attendee`) + tasks/notes (`.mentions`) that point at the person.
    /// Returns raw endpoints grouped by kind; callers resolve the concrete rows.
    public func aggregate(_ person: Person) throws -> PersonAggregate {
        var result = PersonAggregate()
        for edge in try links.backlinks(to: (.person, person.id)) {
            switch (edge.linkKind, edge.fromKind) {
            case (.attendee, .meeting):
                result.meetings.append(edge.fromID)
            case (.mentions, .task):
                result.tasks.append(edge.fromID)
            case (.mentions, .note):
                result.notes.append(edge.fromID)
            default:
                continue
            }
        }
        return result
    }

    // MARK: - Helpers

    /// Unions two alias lists, dropping empties and case/diacritic-insensitive
    /// duplicates, preserving first-seen order.
    static func mergedAliases(_ base: [String], _ incoming: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for alias in base + incoming {
            let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = fold(trimmed)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(trimmed)
        }
        return out
    }

    /// Case/diacritic-insensitive fold for name matching (mirrors `Tokenizer`).
    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Identity key for de-duplicating a `Link` by endpoints + edge label.
    static func edgeKey(_ edge: Link) -> String {
        "\(edge.fromKind.rawValue):\(edge.fromID.uuidString):\(edge.toKind.rawValue):\(edge.toID.uuidString):\(edge.linkKind.rawValue)"
    }
}

public enum PersonMergeError: Error, Equatable {
    case cannotMergeIntoSelf(personID: UUID)
    case sourceAlreadyDeleted(personID: UUID)
}
