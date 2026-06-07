import Foundation
import NexusCore

/// Pure, value-level mutations over a `[Block]` array used by the native editor.
///
/// The editor never mutates `Note.contentData` directly — it works on a decoded
/// `[Block]` array via these helpers, then hands the result to
/// `NoteRepository.updateContent(_:blocks:)`, which re-encodes, reconciles the
/// mirror (Link/Task), and saves in one transaction (spec §6.4).
///
/// All operations preserve block `id`s where the block survives — the ids anchor
/// the reconciler's cross-object mirror (spec §4.3); regenerating an id on a plain
/// edit would orphan a `containsTask`/`embed` edge. A new block gets a fresh id.
public enum BlockListOps {

    /// The block kinds the editor can create from the "insert block" affordance.
    /// `todo` mints a `TaskItem` through the reconciler when persisted (a fresh
    /// `taskRef` is generated here, not bound to any existing task yet).
    public enum NewBlock: Sendable, Equatable {
        case paragraph
        case heading(level: Int)
        case todo
        case bulleted
        case numbered
        case quote
        case code
        case divider
    }

    /// Build an empty `Block` of the requested kind, with a fresh stable id.
    public static func makeBlock(_ new: NewBlock) -> Block {
        switch new {
        case .paragraph:
            return Block(kind: .paragraph(runs: []))
        case .heading(let level):
            return Block(kind: .heading(level: max(1, min(level, 6)), runs: []))
        case .todo:
            return Block(kind: .todo(taskRef: UUID(), runs: []))
        case .bulleted:
            return Block(kind: .bulleted(runs: []))
        case .numbered:
            return Block(kind: .numbered(runs: []))
        case .quote:
            return Block(kind: .quote(runs: []))
        case .code:
            return Block(kind: .code(language: nil, text: ""))
        case .divider:
            return Block(kind: .divider)
        }
    }

    /// Insert `block` immediately after the block with id `afterID`. When `afterID`
    /// is nil (or not found), append to the end. Returns the new array.
    public static func insert(_ block: Block, after afterID: UUID?, in blocks: [Block]) -> [Block] {
        guard let afterID, let index = blocks.firstIndex(where: { $0.id == afterID }) else {
            return blocks + [block]
        }
        var result = blocks
        result.insert(block, at: index + 1)
        return result
    }

    /// Remove the block with `id`. No-op if absent.
    public static func remove(id: UUID, in blocks: [Block]) -> [Block] {
        blocks.filter { $0.id != id }
    }

    /// Move the block at `offsets` to `destination` (SwiftUI `onMove` semantics).
    public static func move(in blocks: [Block], from offsets: IndexSet, to destination: Int) -> [Block] {
        var result = blocks
        result.move(fromOffsets: offsets, toOffset: destination)
        return result
    }

    /// Replace the inline runs of a text-bearing block (paragraph/heading/bulleted/
    /// numbered/quote). No-op for blocks without runs (todo runs are edited through
    /// the repository's checkbox seam so the task title stays the source of truth).
    public static func setRuns(_ runs: [InlineRun], forBlock id: UUID, in blocks: [Block]) -> [Block] {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return blocks }
        var result = blocks
        switch result[index].kind {
        case .paragraph:
            result[index].kind = .paragraph(runs: runs)
        case .heading(let level, _):
            result[index].kind = .heading(level: level, runs: runs)
        case .bulleted:
            result[index].kind = .bulleted(runs: runs)
        case .numbered:
            result[index].kind = .numbered(runs: runs)
        case .quote:
            result[index].kind = .quote(runs: runs)
        default:
            return blocks
        }
        return result
    }

    /// Replace the text of a code block, keeping its `id` and language.
    public static func setCode(_ text: String, forBlock id: UUID, in blocks: [Block]) -> [Block] {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return blocks }
        var result = blocks
        guard case .code(let language, _) = result[index].kind else { return blocks }
        result[index].kind = .code(language: language, text: text)
        return result
    }

    /// Replace the raw HTML of an `html(raw:)` block, keeping its `id`.
    public static func setHTML(_ raw: String, forBlock id: UUID, in blocks: [Block]) -> [Block] {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return blocks }
        var result = blocks
        guard case .html = result[index].kind else { return blocks }
        result[index].kind = .html(raw: raw)
        return result
    }

    /// Convert a text-bearing block to a different text-bearing kind, preserving its
    /// runs and id. Used by the slash/insert affordance to retype an existing line
    /// (e.g. paragraph → heading). Non-text source/target kinds are left untouched.
    public static func convert(blockID id: UUID, to new: NewBlock, in blocks: [Block]) -> [Block] {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return blocks }
        let runs = textRuns(of: blocks[index].kind)
        guard let runs else { return blocks }
        var result = blocks
        switch new {
        case .paragraph:
            result[index].kind = .paragraph(runs: runs)
        case .heading(let level):
            result[index].kind = .heading(level: max(1, min(level, 6)), runs: runs)
        case .bulleted:
            result[index].kind = .bulleted(runs: runs)
        case .numbered:
            result[index].kind = .numbered(runs: runs)
        case .quote:
            result[index].kind = .quote(runs: runs)
        case .todo:
            result[index].kind = .todo(taskRef: UUID(), runs: runs)
        case .code, .divider:
            // Not a runs-preserving conversion target.
            return blocks
        }
        return result
    }

    /// Extract the inline runs of a text-bearing block kind, or nil for kinds
    /// without runs.
    public static func textRuns(of kind: BlockKind) -> [InlineRun]? {
        switch kind {
        case .paragraph(let runs),
            .heading(_, let runs),
            .todo(_, let runs),
            .bulleted(let runs),
            .numbered(let runs),
            .quote(let runs):
            return runs
        case .code, .divider, .image, .embed, .table, .html:
            return nil
        }
    }
}
