import Foundation

extension InboxItem {
    var nexusInboxSourceLabel: String {
        let normalized =
            sourceID
            .replacingOccurrences(of: "tasks.", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        guard !normalized.isEmpty else { return "Inbox" }
        return
            normalized
            .split(separator: " ")
            .map { word in
                let lower = word.lowercased()
                if lower == "github" { return "GitHub" }
                if lower == "no" { return "No" }
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }

    /// SF Symbol for the row's leading source glyph, mirroring the accepted
    /// Inbox oracle (`Lab/InboxPreview.swift` `InboxRowView.item.icon`). Pure
    /// presentation derivation over the EXISTING `sourceID` / derived
    /// `InboxItemCategory` — no new field/schema/query (§5-safe, same class as
    /// `nexusInboxSourceLabel`). Buckets 1:1 with `InboxSectionBuilder`:
    /// `tasks.no-date` → NO DATE, `tasks.snoozed` → SNOOZED, `.digests` →
    /// E-MAIL, `.mentions` → MENTIONS. The `tray` fallback covers orphan /
    /// `.people` items, which the section builder drops anyway (no oracle
    /// section), so it is never actually rendered today.
    var nexusInboxSourceIcon: String {
        if sourceID == "tasks.no-date" { return "circle" }
        if sourceID == "tasks.snoozed" { return "moon.zzz" }
        switch category {
        case .digests: return "envelope"
        case .mentions: return "at"
        case .people, .tasks: return "tray"
        }
    }

    var nexusInboxRelativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
}
