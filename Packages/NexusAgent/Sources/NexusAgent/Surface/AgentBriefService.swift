import Foundation
import NexusCore
import SwiftData
import SwiftUI

public struct AgentBriefCounts: Sendable, Hashable {
    public let overdue: Int
    public let today: Int
    public let noDate: Int
    public let awaiting: Int

    public init(overdue: Int, today: Int, noDate: Int, awaiting: Int) {
        self.overdue = overdue
        self.today = today
        self.noDate = noDate
        self.awaiting = awaiting
    }
}

public struct AgentBriefRequest: Sendable, Equatable {
    public let counts: AgentBriefCounts
    public let firstTitles: [String]
    public let now: Date

    public init(counts: AgentBriefCounts, firstTitles: [String], now: Date) {
        self.counts = counts
        self.firstTitles = firstTitles
        self.now = now
    }
}

@MainActor
public protocol AgentBriefServiceProtocol: Sendable {
    func brief(for request: AgentBriefRequest) async -> String
}

/// The tier of the model path that produced a brief, ordered so a higher tier
/// supersedes a lower one. Stored on the daily note as `briefSource` so any
/// device can decide whether to ADOPT a peer's note (its tier ≥ mine) or
/// REGENERATE to upgrade it (my tier > the note's). `nil`/unknown labels map to
/// the lowest tier (`.template`), so a note minted by `DailyNoteService` (no
/// source recorded) is always upgradeable.
public enum AgentBriefSource: String, Sendable, Comparable {
    /// Deterministic template — lowest. (Not produced by this service, but a
    /// peer flow or a future deterministic fallback may write it.)
    case template
    /// The injected `legacy` fallback closure (no on-device Gemma runtime).
    case legacy
    /// The on-device agent runtime (Gemma) — highest.
    case agent

    private var rank: Int {
        switch self {
        case .template: 0
        case .legacy: 1
        case .agent: 2
        }
    }

    public static func < (lhs: AgentBriefSource, rhs: AgentBriefSource) -> Bool {
        lhs.rank < rhs.rank
    }

    /// Lenient decode: an unknown/missing label is treated as the lowest tier.
    public static func tier(forRawValue raw: String?) -> AgentBriefSource {
        guard let raw, let source = AgentBriefSource(rawValue: raw) else { return .template }
        return source
    }
}

/// Read-back of the canonical daily note's brief, used by the resolution policy
/// to decide ADOPT vs REGENERATE.
public struct AgentBriefNoteSnapshot: Sendable, Equatable {
    public let plainText: String
    public let inputsHash: String?
    public let source: String?
    /// Most-recent write time of the note (for the near-simultaneous-write damp).
    public let updatedAt: Date

    public init(plainText: String, inputsHash: String?, source: String?, updatedAt: Date) {
        self.plainText = plainText
        self.inputsHash = inputsHash
        self.source = source
        self.updatedAt = updatedAt
    }
}

@MainActor
public protocol AgentBriefDailyNoteWriting: Sendable {
    /// Upsert the canonical daily note with `brief`, stamping the deterministic
    /// `inputsHash` and the producing `source` tier into `note.properties`.
    func upsertDailyNote(
        for request: AgentBriefRequest,
        brief: String,
        inputsHash: String,
        source: AgentBriefSource
    ) throws
    /// Today's canonical daily note read-back, or `nil` when none exists yet.
    func todayDailyNote(for request: AgentBriefRequest) throws -> AgentBriefNoteSnapshot?
}

@MainActor
public final class AgentBriefDailyNoteWriter: AgentBriefDailyNoteWriting, @unchecked Sendable {
    /// `note.properties` keys carrying the brief's provenance. Stored inside the
    /// CloudKit-synced `propertiesJSON` blob (no schema column, no migration).
    static let inputsHashKey = "briefInputsHash"
    static let sourceKey = "briefSource"
    /// Two devices regenerating within this window (same inputs) must not clobber
    /// each other — the second write is damped (advisor #4).
    static let recentWriteWindow: TimeInterval = 2 * 60

    private let modelContext: ModelContext
    private let calendar: Calendar

    public init(modelContext: ModelContext, calendar: Calendar = .current) {
        self.modelContext = modelContext
        self.calendar = calendar
    }

    public func upsertDailyNote(
        for request: AgentBriefRequest,
        brief: String,
        inputsHash: String,
        source: AgentBriefSource
    ) throws {
        let text = brief.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Shared identity convention (NexusCore): the user-facing "Today's
        // note" flow (`DailyNoteService`) resolves the SAME title/tags, so both
        // flows agree on one daily note per day.
        let title = DailyNoteConvention.title(for: request.now, calendar: calendar)
        let tags = DailyNoteConvention.tags(for: request.now, calendar: calendar)
        let blocks = MarkdownBlockParser.parse(Self.strippingDigestMarkers(from: text))
        let repository = NoteRepository(context: modelContext, now: { request.now })

        if let existing = try findExistingDailyNote(title: title) {
            // Near-simultaneous-write damp (advisor #4): when the note was written
            // moments ago AND the inputs have not changed (a quality-upgrade or a
            // redundant rewrite — NOT an evolving brief), skip entirely so two
            // peers regenerating at the same time can't clobber each other. The
            // service's always-read-back makes this transparent (it returns the
            // surviving note's text). An EVOLVING brief (hash changed) bypasses
            // the damp — fresh inputs must always land.
            // A tier UPGRADE (e.g. legacy→agent) is the intended improvement, NOT
            // a clobber — it must bypass the damp, else two near-clocked devices
            // could never upgrade a note and the quality policy is silently
            // defeated. Thrash is bounded instead by the service's once-per-day
            // upgrade latch (a same-tier re-race here reads back the survivor).
            let existingTier = AgentBriefSource.tier(forRawValue: Self.property(existing, Self.sourceKey))
            let inputsChanged = Self.property(existing, Self.inputsHashKey) != inputsHash
            let writtenRecently = request.now.timeIntervalSince(existing.updatedAt) < Self.recentWriteWindow
            let isTierUpgrade = source > existingTier
            if writtenRecently && !inputsChanged && !isTierUpgrade { return }

            // Identity-stable (SW1): `brief()` re-runs this on every Today read,
            // including cache-hits. Skip the rewrite when the brief content is
            // unchanged — `plainText` is taskRef-independent, so an identical brief
            // compares equal even though a re-parse mints fresh checkbox refs.
            // Avoids churning the note + firing reloadAllTimelines on every read.
            // The provenance properties still get refreshed when they drift (a
            // quality-upgrade keeps identical prose but raises `briefSource`).
            let newPlainText = NotePlainTextFlattener.plainText(for: blocks)
            let provenanceUnchanged =
                Self.property(existing, Self.inputsHashKey) == inputsHash
                && Self.property(existing, Self.sourceKey) == source.rawValue
            let contentUnchanged = existing.plainText == newPlainText && existing.tags == tags
            guard !(contentUnchanged && provenanceUnchanged) else { return }
            if !contentUnchanged {
                try repository.updateFields(existing, title: title, tags: tags, role: .dailyNote)
                try repository.updateContent(existing, blocks: blocks)
            }
            try Self.stampProvenance(existing, repository: repository, inputsHash: inputsHash, source: source)
        } else {
            let note = try repository.create(title: title, blocks: blocks, role: .dailyNote, tags: tags)
            try Self.stampProvenance(note, repository: repository, inputsHash: inputsHash, source: source)
        }
    }

    public func todayDailyNote(for request: AgentBriefRequest) throws -> AgentBriefNoteSnapshot? {
        let title = DailyNoteConvention.title(for: request.now, calendar: calendar)
        guard let note = try findExistingDailyNote(title: title) else { return nil }
        return AgentBriefNoteSnapshot(
            plainText: note.plainText,
            inputsHash: Self.property(note, Self.inputsHashKey),
            source: Self.property(note, Self.sourceKey),
            updatedAt: note.updatedAt
        )
    }

    /// Merge the two provenance keys into the note's existing property bag
    /// (last-wins on key), leaving any user/import properties untouched. Routed
    /// through `NoteRepository.updateProperties` — views/agent never write the blob.
    private static func stampProvenance(
        _ note: Note,
        repository: NoteRepository,
        inputsHash: String,
        source: AgentBriefSource
    ) throws {
        var merged = note.properties.filter { $0.key != inputsHashKey && $0.key != sourceKey }
        merged.append(NoteProperty(key: inputsHashKey, value: .string(inputsHash)))
        merged.append(NoteProperty(key: sourceKey, value: .string(source.rawValue)))
        try repository.updateProperties(note, properties: merged)
    }

    private static func property(_ note: Note, _ key: String) -> String? {
        guard let value = note.properties.first(where: { $0.key == key })?.value,
            case .string(let string) = value
        else { return nil }
        return string
    }

    /// The Today hero brief carries `[[accent]]…[[/accent]]` / `[[mono]]…[[/mono]]`
    /// emphasis markers that `DigestRenderer` turns into styled runs on that
    /// surface. A persisted daily note has no such renderer, so the markers must
    /// be stripped before storing — otherwise the Notes list and editor show the
    /// literal `[[accent]]…` wire tokens. Kept as an explicit token list (rather
    /// than importing `DigestRenderer`) to keep NexusAgent decoupled from
    /// TasksFeature; the token set mirrors `DigestRenderer`'s emphasis/mono spans.
    static func strippingDigestMarkers(from text: String) -> String {
        var result = text
        for marker in ["[[accent]]", "[[/accent]]", "[[mono]]", "[[/mono]]"] {
            result = result.replacingOccurrences(of: marker, with: "")
        }
        return result
    }

    private func findExistingDailyNote(title: String) throws -> Note? {
        // Sorted by createdAt so duplicate-titled legacy twins resolve to the
        // OLDEST note deterministically — same rule as `DailyNoteService`, so
        // the agent upsert and the user's "Today" action land on ONE note.
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\Note.createdAt)]
        )
        return try modelContext.fetch(descriptor)
            .first { $0.role == .dailyNote && $0.title == title }
    }
}

@MainActor
public final class AgentBriefService: AgentBriefServiceProtocol, @unchecked Sendable {
    private struct CacheKey: Hashable {
        let dayBucket: Date
        let counts: AgentBriefCounts
        let firstTitles: [String]
    }

    private struct CacheEntry {
        let value: String
        let timestamp: Date
    }

    private let runtime: AgentRuntime?
    private let threadStore: AgentThreadStore?
    private let pinnedThreadTitle: String
    private let legacy: @Sendable (AgentBriefRequest) async -> String
    private let isEnabled: @Sendable () -> Bool
    private let calendar: Calendar
    private let ttl: TimeInterval
    private let dailyNoteWriter: (any AgentBriefDailyNoteWriting)?
    private var cache: [CacheKey: CacheEntry] = [:]
    private var inFlight: [CacheKey: Task<String, Never>] = [:]
    /// Per-dayKey latch: a device attempts a quality-upgrade regeneration (note
    /// exists, inputs match, peer tier < mine) AT MOST ONCE per day. Without it
    /// every store-change reload would re-run the runtime to re-upgrade a peer's
    /// note that already converged on content (DAMPING — advisor #4).
    private var upgradeAttemptedDayKeys: Set<String> = []

    public init(
        runtime: AgentRuntime?,
        threadStore: AgentThreadStore?,
        pinnedThreadTitle: String = "Daily Briefs",
        legacy: @escaping @Sendable (AgentBriefRequest) async -> String,
        isEnabled: @escaping @Sendable () -> Bool = { true },
        calendar: Calendar = .current,
        ttl: TimeInterval = 30 * 60,
        dailyNoteWriter: (any AgentBriefDailyNoteWriting)? = nil
    ) {
        self.runtime = runtime
        self.threadStore = threadStore
        self.pinnedThreadTitle = pinnedThreadTitle
        self.legacy = legacy
        self.isEnabled = isEnabled
        self.calendar = calendar
        self.ttl = ttl
        self.dailyNoteWriter = dailyNoteWriter
    }

    public func brief(for request: AgentBriefRequest) async -> String {
        let agentAvailable = isEnabled() && runtime != nil && threadStore != nil
        let myTier: AgentBriefSource = agentAvailable ? .agent : .legacy

        // No canonical-note seam injected (pure-runtime / legacy use, e.g. the
        // `runtimeSuccessReturnsAgentText` test): keep the original behavior —
        // generate and return the raw text, but route through `regenerate` so the
        // in-memory TTL cache + in-flight coalescing still apply (the no-writer
        // path of `upsertAndReadBack` returns the generated text verbatim).
        guard let dailyNoteWriter else {
            return await regenerate(
                for: request,
                agentAvailable: agentAvailable,
                source: myTier,
                inputsHash: Self.inputsHash(for: request, calendar: calendar)
            )
        }

        // ── Resolution policy (advisor #1/#2): runs BEFORE the enabled-guard AND
        // before the TTL cache so a peer's synced note is adopted instead of a
        // device returning its own stale self-generated text. This is the core
        // anti-ping-pong mechanism — it must apply on BOTH the agent and the
        // legacy-only device.
        let inputsHash = Self.inputsHash(for: request, calendar: calendar)
        let dayKey = DailyNoteConvention.dayKey(for: request.now, calendar: calendar)
        let snapshot = try? dailyNoteWriter.todayDailyNote(for: request)

        if let snapshot, snapshot.inputsHash == inputsHash {
            let noteTier = AgentBriefSource.tier(forRawValue: snapshot.source)
            if noteTier >= myTier {
                // ADOPT: identical inputs already briefed at ≥ my tier → return
                // the canonical note's text, no LLM, no write. Peers converge here.
                return adopt(snapshot, key: cacheKey(for: request))
            }
            // QUALITY UPGRADE candidate (note tier < mine). Damped to once/day so
            // a device doesn't re-run the runtime on every reload to re-upgrade a
            // peer's already-converged note. When damped, adopt the lower-tier note.
            guard !upgradeAttemptedDayKeys.contains(dayKey) else {
                return adopt(snapshot, key: cacheKey(for: request))
            }
            upgradeAttemptedDayKeys.insert(dayKey)
            return await regenerate(for: request, agentAvailable: agentAvailable, source: myTier, inputsHash: inputsHash)
        }

        // REGENERATE: no note for today, or the inputs evolved (hash changed).
        return await regenerate(for: request, agentAvailable: agentAvailable, source: myTier, inputsHash: inputsHash)
    }

    /// Read-back the canonical note for display and seed the TTL cache with it,
    /// so the cache mirrors exactly what was returned (advisor #4).
    private func adopt(_ snapshot: AgentBriefNoteSnapshot, key: CacheKey) -> String {
        cache[key] = CacheEntry(value: snapshot.plainText, timestamp: Date.now)
        return snapshot.plainText
    }

    /// Generate (via runtime/legacy), upsert the canonical note with provenance,
    /// then return the note's READ-BACK `plainText` so display == synced note.
    /// Falls back to the generated text only if the read-back is unavailable.
    private func regenerate(
        for request: AgentBriefRequest,
        agentAvailable: Bool,
        source: AgentBriefSource,
        inputsHash: String
    ) async -> String {
        let key = cacheKey(for: request)
        let now = Date.now
        if let entry = cache[key], now.timeIntervalSince(entry.timestamp) < ttl {
            return entry.value
        }
        cache[key] = nil

        if let task = inFlight[key] {
            return await task.value
        }

        let task = Task { @MainActor [self] in
            let generated = await generateBrief(for: request, agentAvailable: agentAvailable)
            let text = upsertAndReadBack(
                for: request,
                generated: generated,
                source: source,
                inputsHash: inputsHash
            )
            cache[key] = CacheEntry(value: text, timestamp: Date.now)
            inFlight[key] = nil
            return text
        }
        inFlight[key] = task
        return await task.value
    }

    private func generateBrief(for request: AgentBriefRequest, agentAvailable: Bool) async -> String {
        guard agentAvailable, let runtime, let threadStore else {
            return await legacy(request)
        }
        return await resolveBrief(for: request, runtime: runtime, threadStore: threadStore)
    }

    /// Upsert the canonical note (provenance-stamped), then read it back so the
    /// returned + cached value is the synced note's `plainText`. The
    /// near-simultaneous-write damp lives in the writer's content-unchanged guard;
    /// the always-read-back makes a damped write transparent — we still return the
    /// peer's text. Falls back to the raw generated text if the writer/read-back fails.
    private func upsertAndReadBack(
        for request: AgentBriefRequest,
        generated: String,
        source: AgentBriefSource,
        inputsHash: String
    ) -> String {
        guard let dailyNoteWriter else { return generated }
        try? dailyNoteWriter.upsertDailyNote(
            for: request,
            brief: generated,
            inputsHash: inputsHash,
            source: source
        )
        if let snapshot = try? dailyNoteWriter.todayDailyNote(for: request), !snapshot.plainText.isEmpty {
            return snapshot.plainText
        }
        return generated
    }

    /// Deterministic, cross-device-stable brief-inputs digest (advisor #3): a
    /// fixed string-concat over SYNCED domain data only — the dayKey, the four
    /// counts, and the first 3 task titles (same prefix the cache key uses). NO
    /// wall-clock beyond dayKey, NO locale formatting, NO `Hasher` (whose seed
    /// varies per launch). Two devices with the same synced data produce the same
    /// string, so the value compares equal across devices and launches.
    static func inputsHash(for request: AgentBriefRequest, calendar: Calendar) -> String {
        let dayKey = DailyNoteConvention.dayKey(for: request.now, calendar: calendar)
        let counts = request.counts
        let titles = request.firstTitles.prefix(3).joined(separator: "\u{1F}")
        return "\(dayKey)|o\(counts.overdue)|t\(counts.today)|n\(counts.noDate)|a\(counts.awaiting)|\(titles)"
    }

    private func resolveBrief(
        for request: AgentBriefRequest,
        runtime: AgentRuntime,
        threadStore: AgentThreadStore
    ) async -> String {
        do {
            let threadID = try pinnedThreadID(in: threadStore)
            let response = try await runtime.runTurn(
                AgentTurnRequest(
                    threadID: threadID,
                    userMessage: Self.prompt(for: request),
                    scope: "global"
                )
            )
            guard response.haltReason == .completed else {
                return await legacy(request)
            }

            let raw =
                response.finalAssistantContent?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let content = Self.strippingLeadingPreamble(from: raw)
            return content.isEmpty ? await legacy(request) : content
        } catch {
            return await legacy(request)
        }
    }

    private func cacheKey(for request: AgentBriefRequest) -> CacheKey {
        CacheKey(
            dayBucket: calendar.startOfDay(for: request.now),
            counts: request.counts,
            firstTitles: Array(request.firstTitles.prefix(3))
        )
    }

    private func pinnedThreadID(in threadStore: AgentThreadStore) throws -> UUID {
        if let existing = try threadStore.allActive().first(where: { $0.title == pinnedThreadTitle }) {
            return existing.id
        }
        return try threadStore.create(title: pinnedThreadTitle)
    }

    private static func prompt(for request: AgentBriefRequest) -> String {
        let counts = request.counts
        let titles = request.firstTitles.prefix(3).map { "- \($0)" }.joined(separator: "\n")
        let formattedDate = Self.dateFormatter.string(from: request.now)
        return """
            Write today's brief for the Today view in Nexus.
            Keep the tone concrete, calm, and operational. Return only the finished brief.
            Start directly with the first sentence of the brief — no preamble, no \
            salutation, no meta-sentence like "Here is a brief…" or "Below is a summary…".
            Format: 1-2 short paragraphs. Use at most two [[accent]]...[[/accent]] markers.

            Date: \(formattedDate)
            Numbers: \(counts.overdue) overdue, \(counts.today) today, \
            \(counts.noDate) with no date, \(counts.awaiting) blocking.
            First tasks:
            \(titles.isEmpty ? "- none" : titles)
            """
    }

    /// Strips a leading meta-preamble sentence the LLM may emit when it paraphrases
    /// its own instruction — e.g. "Here is a brief for the user based on their real
    /// tasks: Three things matter today…". The pattern anchors on known openers
    /// ("here is", "here's", "this is", "below is") that precede "brief" or
    /// "summary" within the same colon-delimited span, then removes everything up to
    /// and including the first colon. `[^:\n]*` prevents the match from crossing a
    /// colon or newline, so a body sentence that itself contains a colon is never
    /// over-stripped.
    nonisolated static func strippingLeadingPreamble(from text: String) -> String {
        // NSRegularExpression is case-insensitive; `(?i)` flag avoids recompiling.
        let pattern =
            #"(?i)^\s*(here is|here'?s|this is|below is)\b[^:\n]*\b(brief|summary)\b[^:\n]*:\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let stripped = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        // Guard: if stripping left nothing useful, return the original.
        let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? text : trimmed
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        // English UI — explicit en_US (system locale may be pl_PL)
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

private struct AgentBriefServiceKey: EnvironmentKey {
    static let defaultValue: (any AgentBriefServiceProtocol)? = nil
}

extension EnvironmentValues {
    public var agentBriefService: (any AgentBriefServiceProtocol)? {
        get { self[AgentBriefServiceKey.self] }
        set { self[AgentBriefServiceKey.self] = newValue }
    }
}
