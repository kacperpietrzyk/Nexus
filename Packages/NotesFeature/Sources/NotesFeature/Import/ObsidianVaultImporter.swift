import Foundation
import NexusCore
import SwiftData

/// Imports an Obsidian vault (a folder tree of `.md` files) into Nexus `Note`s by
/// reading files directly from disk — NO network, NO LLM. The body never passes
/// through a model, so content the usage-policy classifier would block (operational
/// security runbooks) imports cleanly alongside everything else.
///
/// Mirrors `CirclebackImporter` (NexusMeetings): a pure `plan()` (diff vault files
/// against the store's existing notes) feeds a `execute()` that applies it. The
/// plan/skip split is idempotent and resume-safe — re-running only creates what is
/// missing, keyed on `(title, folderPath)` because `Note` has no `externalSourceID`.
public struct ObsidianVaultImporter: Sendable {
    public init() {}

    // MARK: - Pure derivations

    /// Note title = file name without the `.md` extension (the on-disk name is the
    /// canonical title; entities like `&` are already literal on the filesystem).
    public static func title(forFileName fileName: String) -> String {
        fileName.hasSuffix(".md") ? String(fileName.dropLast(3)) : fileName
    }

    /// Strips a well-formed LEADING YAML frontmatter fence (`---` … `---`) so only
    /// the markdown body reaches `MarkdownBlockParser` (which treats a leading `---`
    /// as a divider). Robust to arbitrary YAML: a simple fence scan, not the
    /// narrow-subset `MarkdownFrontmatterCoder`. Frontmatter is intentionally not
    /// carried (matches the established landed-note convention). A non-leading `---`
    /// (a real divider) or an unterminated fence is left untouched.
    public static func body(strippingFrontmatterFrom content: String) -> String {
        let lines = content.components(separatedBy: "\n")
        guard lines.first == "---" else { return content }
        guard let closeIndex = lines.dropFirst().firstIndex(of: "---") else { return content }
        var bodyLines = Array(lines[(closeIndex + 1)...])
        if bodyLines.first?.isEmpty == true { bodyLines.removeFirst() }  // drop one blank separator
        return bodyLines.joined(separator: "\n")
    }

    /// Folder placement = the file's parent directory, vault-relative, normalized
    /// through `NoteFolderPath.normalize` so it matches what the repository stores.
    /// A file at the vault root → `nil` (root placement).
    public static func folderPath(forRelativePath relativePath: String) -> String? {
        let components = relativePath.split(separator: "/").map(String.init)
        guard components.count > 1 else { return nil }
        return NoteFolderPath.normalize(components.dropLast().joined(separator: "/"))
    }

    /// Notes under `90 - Templates` import as reusable templates; everything else
    /// is a free-standing knowledge-base note.
    public static func role(forRelativePath relativePath: String) -> NoteRole {
        relativePath.split(separator: "/").first.map(String.init) == "90 - Templates"
            ? .template : .free
    }

    // MARK: - Discovery

    /// Walks `vaultRoot` recursively for `.md` files, skipping hidden entries
    /// (dotfiles, `.obsidian`, `.notecompanion`) and non-markdown files. Returns
    /// vault-relative paths, sorted for deterministic ordering.
    public static func discover(vaultRoot: URL) throws -> [DiscoveredNote] {
        let fileManager = FileManager.default
        let rootPath = vaultRoot.standardizedFileURL.path
        guard
            let enumerator = fileManager.enumerator(
                at: vaultRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles])
        else { return [] }

        var found: [DiscoveredNote] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "md" {
            let fullPath = url.standardizedFileURL.path
            guard fullPath.hasPrefix(rootPath + "/") else { continue }
            found.append(DiscoveredNote(relativePath: String(fullPath.dropFirst(rootPath.count + 1))))
        }
        return found.sorted { $0.relativePath < $1.relativePath }
    }

    // MARK: - Plan

    /// Pure diff: a discovered note whose `(title, folderPath)` key is already in
    /// `existing` is skipped, otherwise created. No I/O.
    public func plan(discovered: [DiscoveredNote], existing: Set<NoteKey>) -> ObsidianImportPlan {
        var toCreate: [DiscoveredNote] = []
        var toSkip: [DiscoveredNote] = []
        for note in discovered {
            if existing.contains(NoteKey(title: note.title, folderPath: note.folderPath)) {
                toSkip.append(note)
            } else {
                toCreate.append(note)
            }
        }
        return ObsidianImportPlan(toCreate: toCreate, toSkip: toSkip)
    }

    /// Snapshot of the store's existing notes as dedup keys (excludes soft-deleted).
    @MainActor
    public static func existingKeys(in repo: NoteRepository) throws -> Set<NoteKey> {
        let notes = try repo.context.fetch(
            FetchDescriptor<Note>(predicate: #Predicate { $0.deletedAt == nil }))
        return Set(notes.map { NoteKey(title: $0.title, folderPath: $0.folderPath) })
    }

    // MARK: - Execute

    /// Applies `plan.toCreate` against the repository: reads each file, strips
    /// frontmatter, parses markdown to blocks, creates the note and sets its folder.
    /// One file failing (read/parse) is recorded and skipped — it never aborts the run.
    @MainActor
    public func execute(
        plan: ObsidianImportPlan,
        repo: NoteRepository,
        vaultRoot: URL,
        progress: @MainActor (Double) -> Void
    ) async throws -> ObsidianImportResult {
        var created = 0
        var failed = 0
        var errors: [String] = []
        let total = max(1, plan.toCreate.count)

        for (index, discovered) in plan.toCreate.enumerated() {
            await Task.yield()
            do {
                let url = vaultRoot.appendingPathComponent(discovered.relativePath)
                let content = try String(contentsOf: url, encoding: .utf8)
                let blocks = MarkdownBlockParser.parse(Self.body(strippingFrontmatterFrom: content))
                let note = try repo.create(
                    title: discovered.title, blocks: blocks, role: discovered.role)
                if discovered.folderPath != nil {
                    try repo.setFolderPath(note, discovered.folderPath)
                }
                created += 1
            } catch {
                failed += 1
                errors.append("\(discovered.relativePath): \(error.localizedDescription)")
            }
            progress(Double(index + 1) / Double(total))
        }

        return ObsidianImportResult(
            created: created, skipped: plan.toSkip.count, failed: failed, errors: errors)
    }
}

// MARK: - Value types

/// A `.md` file discovered in the vault. Title/folder/role are derived from its
/// vault-relative path.
public struct DiscoveredNote: Equatable, Sendable {
    public let relativePath: String
    public init(relativePath: String) { self.relativePath = relativePath }

    public var fileName: String { (relativePath as NSString).lastPathComponent }
    public var title: String { ObsidianVaultImporter.title(forFileName: fileName) }
    public var folderPath: String? { ObsidianVaultImporter.folderPath(forRelativePath: relativePath) }
    public var role: NoteRole { ObsidianVaultImporter.role(forRelativePath: relativePath) }
}

/// Dedup identity for a note: `Note` carries no external id, so `(title, folderPath)`
/// is the natural key for idempotent import.
public struct NoteKey: Hashable, Sendable {
    public let title: String
    public let folderPath: String?
    public init(title: String, folderPath: String?) {
        self.title = title
        self.folderPath = folderPath
    }
}

public struct ObsidianImportPlan: Sendable {
    public let toCreate: [DiscoveredNote]
    public let toSkip: [DiscoveredNote]
    public init(toCreate: [DiscoveredNote], toSkip: [DiscoveredNote]) {
        self.toCreate = toCreate
        self.toSkip = toSkip
    }
}

public struct ObsidianImportResult: Sendable, Equatable {
    public let created: Int
    public let skipped: Int
    public let failed: Int
    public let errors: [String]
    public init(created: Int, skipped: Int, failed: Int, errors: [String]) {
        self.created = created
        self.skipped = skipped
        self.failed = failed
        self.errors = errors
    }
}
