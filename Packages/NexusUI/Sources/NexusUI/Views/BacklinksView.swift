import NexusCore
import SwiftUI

/// Generic backlinks panel — shows everything that links into the current item.
/// Caller resolves the actual `[any Linkable]` (typically by querying
/// `Link` rows where `toID == currentItem.id` and rehydrating the source items).
/// In Phase 0c we render the resolved list; resolver lives in feature modules.
public struct BacklinksView: View {
    public let items: [any Linkable]
    public let emptyMessage: String
    public let onSelect: ((any Linkable) -> Void)?

    public init(
        items: [any Linkable],
        emptyMessage: String = "No backlinks yet",
        onSelect: ((any Linkable) -> Void)? = nil
    ) {
        self.items = items
        self.emptyMessage = emptyMessage
        self.onSelect = onSelect
    }

    public var body: some View {
        NexusCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Backlinks")
                    .nexusType(.eyebrow)
                    .foregroundStyle(NexusColor.Text.tertiary)

                if items.isEmpty {
                    Text(emptyMessage)
                        .nexusType(.bodySmall)
                        .foregroundStyle(NexusColor.Text.muted)
                        .padding(.vertical, 12)
                } else {
                    VStack(spacing: 0) {
                        ForEach(items, id: \.id) { item in
                            row(for: item)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(for item: any Linkable) -> some View {
        if let onSelect {
            Button {
                onSelect(item)
            } label: {
                ItemRow(item: item)
            }
            .buttonStyle(.plain)
        } else {
            ItemRow(item: item)
        }
    }
}

#Preview("Empty") {
    BacklinksView(items: [])
        .padding(40)
        .background(NexusColor.Background.base)
}

#Preview("With items") {
    BacklinksView(items: [
        TaskItem(title: "Plan 0c overview"),
        TaskItem(title: "Spec §13 — visual design"),
    ])
    .padding(40)
    .background(NexusColor.Background.base)
}
