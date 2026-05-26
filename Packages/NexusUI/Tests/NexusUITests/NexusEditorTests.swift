import SwiftUI
import Testing

@testable import NexusUI

@MainActor
@Test func editor_initializesWithMarkdown() {
    let editor = NexusEditor(markdown: "# Hello\n\nBody **bold**.")
    #expect(editor.rawMarkdown == "# Hello\n\nBody **bold**.")
}

@MainActor
@Test func editor_parsesMarkdownToAttributedString() {
    let editor = NexusEditor(markdown: "**bold** and _italic_ and `code`")
    let attributed = editor.attributed
    #expect(!attributed.characters.isEmpty)
}

@MainActor
@Test func editor_handlesEmptyMarkdown() {
    let editor = NexusEditor(markdown: "")
    let attributed = editor.attributed
    #expect(attributed.characters.isEmpty)
}

@MainActor
@Test func editor_invalidMarkdown_returnsAttributedAnyway() {
    // AttributedString(markdown:) is permissive; truly malformed input
    // becomes plain text. The fallback path always succeeds.
    let editor = NexusEditor(markdown: "[](broken")
    _ = editor.attributed  // does not crash
}
