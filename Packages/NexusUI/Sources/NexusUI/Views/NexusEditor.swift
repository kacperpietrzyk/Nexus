import SwiftUI

/// Read-only Markdown display — Phase 0c shell. Full editing (live preview,
/// `[[wiki-links]]`, slash commands) lands in Phase 2 (Notes module).
///
/// Inline formatting only: `**bold**`, `_italic_`, `` `code` ``, links. Block
/// constructs (`#` headings, `-` bullets, blockquotes, code fences) render as
/// literal characters — Phase 2 will use a real Markdown renderer.
public struct NexusEditor: View {
    public let rawMarkdown: String

    public init(markdown: String) {
        self.rawMarkdown = markdown
    }

    public var attributed: AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        return (try? AttributedString(markdown: rawMarkdown, options: options))
            ?? AttributedString(rawMarkdown)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(attributed)
                    .nexusType(.body)
                    .foregroundStyle(NexusColor.Text.primary)
                    .nexusTextSelectionEnabled()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NexusColor.Background.base)
    }
}

#Preview {
    NexusEditor(
        markdown: """
            # Welcome to Nexus

            This is a **read-only** Markdown shell. Phase 2 will add the live editor
            with `[[wiki-links]]` and slash commands.

            - First bullet
            - Second bullet
            """
    )
    .frame(width: 640, height: 480)
}

extension View {
    /// `.textSelection(.enabled)` on platforms that support it; no-op on watchOS.
    @ViewBuilder
    fileprivate func nexusTextSelectionEnabled() -> some View {
        #if os(macOS) || os(iOS) || os(visionOS)
        self.textSelection(.enabled)
        #else
        self
        #endif
    }
}
