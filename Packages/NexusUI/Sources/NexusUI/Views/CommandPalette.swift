import SwiftUI

/// Action descriptor consumed by `CommandPalette`. App / feature modules
/// register these. Phase 0c only ships the chrome + filter; registrar lives
/// in feature packages (Tasks, Notes, etc.) and the host app.
public struct PaletteAction: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let shortcut: [String]
    public let perform: @MainActor @Sendable () -> Void

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        shortcut: [String] = [],
        perform: @escaping @MainActor @Sendable () -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.shortcut = shortcut
        self.perform = perform
    }
}

/// ⌘K palette chrome — keyboard-first navigation surface.
/// Host app handles presentation (sheet / overlay) and key binding.
public struct CommandPalette: View {
    public let actions: [PaletteAction]
    public let onDismiss: () -> Void

    @State private var query: String = ""

    public init(
        actions: [PaletteAction],
        onDismiss: @escaping () -> Void = {}
    ) {
        self.actions = actions
        self.onDismiss = onDismiss
    }

    /// Pure filter — lower-cased substring match against title + subtitle.
    public static func filter(actions: [PaletteAction], query: String) -> [PaletteAction] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return actions }
        return actions.filter { action in
            action.title.lowercased().contains(trimmed)
                || (action.subtitle?.lowercased().contains(trimmed) ?? false)
        }
    }

    public var body: some View {
        ZStack {
            NexusColor.Background.base.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            paletteContent
                .frame(width: 600)
                .background(
                    NexusColor.Background.raised,
                    in: RoundedRectangle(cornerRadius: NexusRadius.r3, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: NexusRadius.r3, style: .continuous)
                        .strokeBorder(NexusColor.Line.regular, lineWidth: 1)
                }
                .nexusShadow(NexusShadow.pop)
                .padding(.top, 120)
        }
    }

    private var paletteContent: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            Rectangle()
                .fill(NexusColor.Line.hairline)
                .frame(height: 1)
            resultsList
                .frame(maxHeight: 360)
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(NexusColor.Text.tertiary)
            TextField("Search actions…", text: $query)
                .nexusType(.body)
                .foregroundStyle(NexusColor.Text.primary)
                .textFieldStyle(.plain)
            NexusKbd("esc")
        }
    }

    private var resultsList: some View {
        let filtered = Self.filter(actions: actions, query: query)
        return ScrollView {
            VStack(spacing: 0) {
                if filtered.isEmpty {
                    Text("No matches")
                        .nexusType(.bodySmall)
                        .foregroundStyle(NexusColor.Text.muted)
                        .padding(.vertical, 24)
                } else {
                    ForEach(filtered) { action in
                        actionRow(action)
                    }
                }
            }
        }
    }

    private func actionRow(_ action: PaletteAction) -> some View {
        Button {
            action.perform()
            onDismiss()
        } label: {
            PaletteRowLabel(action: action)
        }
        .buttonStyle(.plain)
    }
}

/// Single result row. Highlights on hover with the Linear selected-row
/// treatment: `Background.controlHover` fill plus a leading lime marker.
private struct PaletteRowLabel: View {
    let action: PaletteAction

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(NexusColor.Accent.lime)
                .frame(width: 2)
                .opacity(isHovering ? 1 : 0)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .nexusType(.bodySmall)
                        .foregroundStyle(NexusColor.Text.primary)
                    if let subtitle = action.subtitle {
                        Text(subtitle)
                            .nexusType(.caption)
                            .foregroundStyle(NexusColor.Text.tertiary)
                    }
                }
                Spacer(minLength: 12)
                if !action.shortcut.isEmpty {
                    NexusKbd.combo(action.shortcut)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovering ? NexusColor.Background.controlHover : .clear)
        .contentShape(Rectangle())
        #if !os(watchOS)
        .onHover { isHovering = $0 }
        #endif
    }
}

#Preview {
    CommandPalette(actions: [
        PaletteAction(id: "today.open", title: "Open Today", subtitle: "Tasks", shortcut: ["⌘", "1"]) {},
        PaletteAction(id: "graph.open", title: "Open Knowledge Graph", shortcut: ["⌘", "G"]) {},
        PaletteAction(id: "task.new", title: "New Task", subtitle: "Inbox", shortcut: ["⌘", "N"]) {},
    ])
    .padding(40)
    .background(NexusColor.Background.base)
}
