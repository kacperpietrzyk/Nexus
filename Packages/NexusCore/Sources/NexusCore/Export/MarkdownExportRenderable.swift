import Foundation
import SwiftData

/// Conform a `Linkable` defined OUTSIDE NexusCore (e.g. `Meeting` in
/// NexusMeetings) to own its Markdown export: extra frontmatter fields appended
/// after the base `MarkdownDocument` fields, plus the full Markdown body.
/// `MarkdownExporter` checks this conformance before its built-in note-body
/// special cases, so feature modules join the anti-lock-in export without
/// NexusCore importing them (layer rule: core stays feature-agnostic).
public protocol MarkdownExportRenderable: Linkable {
    /// Extra frontmatter fields, emitted after `deletedAt` and before `links`.
    /// Caller-supplied order is preserved (`MarkdownFrontmatterCoder`
    /// determinism guarantee #1).
    @MainActor func exportFrontmatterExtras() -> [(String, FrontmatterValue)]
    /// Full Markdown body. `context` allows resolving referenced rows (e.g. a
    /// meeting's action-item `TaskItem`s) at export time.
    @MainActor func exportMarkdownBody(in context: ModelContext) -> String
}
