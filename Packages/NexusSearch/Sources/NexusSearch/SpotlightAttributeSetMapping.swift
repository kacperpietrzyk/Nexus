import CoreSpotlight
import Foundation
import NexusCore

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// Pure-function adapter: `IndexedDocument` → `CSSearchableItem` ready for donation.
///
/// Title heuristic: first non-empty line of `text` (handles future Note/Meeting models that
/// concatenate `title + body | transcript`). `contentDescription` is the full text — Spotlight
/// truncates as needed. Empty input yields the kind raw value as title (defensive — DebugItem
/// without a title still surfaces).
public enum SpotlightAttributeSetMapping {

    public static func makeAttributeSet(for document: IndexedDocument) -> CSSearchableItemAttributeSet {
        #if canImport(UniformTypeIdentifiers)
        let attrs = CSSearchableItemAttributeSet(contentType: UTType.text)
        #else
        let attrs = CSSearchableItemAttributeSet(itemContentType: "public.text")
        #endif

        let trimmed = document.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            attrs.title = document.kind.rawValue
        } else {
            attrs.title = String(trimmed.split(whereSeparator: \.isNewline).first ?? Substring(trimmed))
        }
        attrs.contentDescription = document.text
        attrs.contentModificationDate = document.updatedAt
        return attrs
    }

    public static func makeSearchableItem(for document: IndexedDocument) -> CSSearchableItem {
        CSSearchableItem(
            uniqueIdentifier: SpotlightDomain.uniqueIdentifier(kind: document.kind, id: document.id),
            domainIdentifier: SpotlightDomain.subdomain(for: document.kind),
            attributeSet: makeAttributeSet(for: document)
        )
    }
}
