import NexusUI
import SwiftUI

public struct CommandPaletteView: View {
    private static let maxPaletteWidth: CGFloat = 620

    private let registry: CommandRegistry
    private let onDismiss: @MainActor () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var query = ""
    @State private var commands: [any Command] = []
    @State private var availabilityByID: [String: CommandAvailability] = [:]
    @State private var selectedIndex: Int = 0
    @FocusState private var inputFocused: Bool

    public init(
        registry: CommandRegistry = .shared,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        self.registry = registry
        self.onDismiss = onDismiss
    }

    public var body: some View {
        let presentation = CommandPalettePresentation.resolved(
            horizontalSizeClass: horizontalSizeClass
        )

        VStack(spacing: 0) {
            inputRow(presentation: presentation)
            divider
            itemList(presentation: presentation)
            if presentation.showsKeyboardFooter {
                divider
                footerRow
            }
        }
        .containerRelativeFrame(.horizontal) { length, _ in
            min(Self.maxPaletteWidth, length)
        }
        .nexusGlass(.regular, in: RoundedRectangle(cornerRadius: 18))
        .nexusOverlayEnter()
        .padding(.bottom, 120)
        .task { await reload() }
        .onAppear { inputFocused = true }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
            Task { await reload() }
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !commands.isEmpty else { return .ignored }
            selectedIndex = min(commands.count - 1, selectedIndex + 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard !commands.isEmpty else { return .ignored }
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.return) {
            executeSelected()
            return .handled
        }
    }

    private func inputRow(presentation: CommandPalettePresentation) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(NexusColor.Text.tertiary)
            TextField(
                "Search commands...",
                text: $query,
                prompt: Text("Search commands...")
                    .foregroundStyle(NexusColor.Text.muted)
            )
            .textFieldStyle(.plain)
            .font(Font.custom("Geist-Regular", size: 15))
            .foregroundStyle(NexusColor.Text.primary)
            .focused($inputFocused)
            .onSubmit { executeSelected() }
            Spacer()
            if presentation.showsEscapeKey {
                Text("esc")
                    .font(NexusType.metaMono)
                    .foregroundStyle(NexusColor.Text.disabled)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Color.white.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private var divider: some View {
        Rectangle()
            .fill(NexusColor.Line.hairline)
            .frame(height: 1)
    }

    private func itemList(presentation: CommandPalettePresentation) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if commands.isEmpty {
                    // gate: registry.search("") returns ALL commands, so an empty
                    // `commands` with an empty `query` is the pre-`.task` first
                    // frame (or a zero-command registry) — render nothing rather
                    // than the broken query-interpolated copy. The oracle no-match
                    // view shows only when the user actually typed a non-match.
                    if !query.isEmpty {
                        noMatchView
                    }
                } else {
                    ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                        commandRow(
                            command,
                            index: index,
                            availability: availability(for: command),
                            isHighlighted: index == selectedIndex,
                            presentation: presentation
                        )
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 380)
    }

    private var noMatchView: some View {
        VStack(spacing: 12) {
            Circle()
                .stroke(
                    NexusColor.Text.disabled,
                    style: StrokeStyle(lineWidth: 1.3, dash: [2, 3.5])
                )
                .frame(width: 26, height: 26)
                // decorative dashed ring — the text carries the meaning.
                .accessibilityHidden(true)
            // §8: raw Geist-SemiBold/Geist-Regular — oracle weights not
            // expressible via a semantic token; locked stopgap, same precedent
            // as the raw GeistMono-* / Geist-Medium usages above.
            Text("Brak dopasowania")
                .font(Font.custom("Geist-SemiBold", size: 15))
                .foregroundStyle(NexusColor.Text.secondary)
            Text("Nic nie pasuje do „\(query)”.")
                .font(Font.custom("Geist-Regular", size: 12.5))
                .foregroundStyle(NexusColor.Text.muted)
            // §10: the oracle's "↩ zapytaj Nexusa zamiast" pill is omitted
            // entirely — no reachable query→agent backend at the palette layer
            // (init exposes only CommandRegistry + onDismiss; both mounts pass
            // dismiss only). Omitted = gone (no orphan ↩, no faked routing).
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 16)
        // title + query subtitle are one announcement, not two focus stops.
        .accessibilityElement(children: .combine)
    }

    private var footerRow: some View {
        HStack(spacing: 14) {
            foot("↑↓", "nawiguj")
            foot("↩", "otwórz")
            // Oracle's `⌘↩ akcja` hint is §10-omitted: commandRow exposes no
            // secondary command-row action, so the cue is not surfaced
            // (formal §10 record lands in the slice-3/4 counts closeout).
            Spacer()
            Text("Nexus")
                .font(NexusType.metaMono)
                .foregroundStyle(NexusColor.Text.disabled)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    private func foot(_ k: String, _ s: String) -> some View {
        HStack(spacing: 5) {
            Text(k)
                .font(NexusType.metaMono)
                .foregroundStyle(NexusColor.Text.tertiary)
            Text(s)
                .font(Font.custom("Geist-Regular", size: 11))
                .foregroundStyle(NexusColor.Text.disabled)
        }
    }

    private func commandRow(
        _ command: any Command,
        index: Int,
        availability: CommandAvailability,
        isHighlighted: Bool,
        presentation: CommandPalettePresentation
    ) -> some View {
        let isEnabled = availability.isEnabled
        let disabledReason = availability.disabledReason
        // Oracle row idiom: bare 16pt icon + medium title + mono hint, highlight
        // is solely the §2 Glass.surface3 fill + achromatic fg swap. The old
        // accent tile / leading rule / accent fill do not exist in the oracle
        // and are removed outright (not retoned). Button + execute/onDismiss is
        // kept as the interactivity scaffold the non-interactive oracle omits.
        return Button {
            execute(command)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: command.iconName)
                    .font(.system(size: 12))
                    .foregroundStyle(
                        rowIconColor(isHighlighted: isHighlighted, isEnabled: isEnabled)
                    )
                    .frame(width: 16)
                    // decorative SF Symbol — title carries the meaning.
                    .accessibilityHidden(true)
                // §8: raw Geist-Medium 13 — oracle weight not expressible via a
                // semantic token (.bodySmall resolves Geist-Regular); locked
                // stopgap, same precedent as the raw GeistMono-* footer usages.
                VStack(alignment: .leading, spacing: 2) {
                    Text(command.title)
                        .font(Font.custom("Geist-Medium", size: 13))
                        .foregroundStyle(
                            rowTitleColor(isHighlighted: isHighlighted, isEnabled: isEnabled)
                        )
                    if let disabledReason {
                        Text(disabledReason)
                            .font(Font.custom("Geist-Regular", size: 11))
                            .foregroundStyle(NexusColor.Text.disabled)
                            .lineLimit(1)
                    }
                }
                Spacer()
                // shortcut is legitimately empty for some commands; render only
                // when non-empty — no fabricated hint string (§10).
                if presentation.showsCommandShortcuts, !command.shortcut.isEmpty {
                    Text(command.shortcut.joined(separator: " "))
                        .font(NexusType.metaMono)
                        .foregroundStyle(NexusColor.Text.disabled)
                        // visual-only shortcut tokens — not spoken.
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            // frame after padding, before background so the highlight fill and
            // the full-row tap target span the row (oracle relies on its inner
            // Spacer; production keeps the explicit row scaffolding).
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isHighlighted ? NexusColor.Glass.surface3 : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        #if os(macOS)
        .onHover { hovering in
            guard hovering, isEnabled else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                selectedIndex = index
            }
        }
        #endif
        // subtitle is oracle-absent visually; real descriptive text retained
        // non-visually via accessibility.
        .accessibilityLabel(command.title)
        .accessibilityValue(isEnabled ? "" : "Disabled")
        .accessibilityHint(disabledReason ?? command.subtitle ?? "")
    }

    @MainActor
    private func reload() async {
        let matchingCommands = await registry.search(query)
        let matchingAvailability = await registry.availabilitySnapshot(
            for: matchingCommands.map(\.id)
        )
        commands = matchingCommands
        availabilityByID = matchingAvailability
        if selectedIndex >= commands.count {
            selectedIndex = max(0, commands.count - 1)
        }
    }

    private func availability(for command: any Command) -> CommandAvailability {
        availabilityByID[command.id] ?? .enabled
    }

    private func rowIconColor(isHighlighted: Bool, isEnabled: Bool) -> Color {
        guard isEnabled else { return NexusColor.Text.disabled }
        return isHighlighted ? NexusColor.Text.primary : NexusColor.Text.muted
    }

    private func rowTitleColor(isHighlighted: Bool, isEnabled: Bool) -> Color {
        guard isEnabled else { return NexusColor.Text.disabled }
        return isHighlighted ? NexusColor.Text.primary : NexusColor.Text.secondary
    }

    @MainActor
    private func executeSelected() {
        guard commands.indices.contains(selectedIndex) else { return }
        execute(commands[selectedIndex])
    }

    @MainActor
    private func execute(_ command: any Command) {
        Task {
            do {
                try await registry.execute(id: command.id)
                onDismiss()
            } catch CommandRegistryError.disabledCommand {
                await reload()
            } catch {
                onDismiss()
            }
        }
    }
}

enum CommandPalettePlatform {
    case iOS
    case macOS

    static var current: Self {
        #if os(iOS)
        .iOS
        #else
        .macOS
        #endif
    }
}

struct CommandPalettePresentation {
    let showsEscapeKey: Bool
    let showsCommandShortcuts: Bool
    let showsKeyboardFooter: Bool

    static func resolved(
        horizontalSizeClass: UserInterfaceSizeClass?,
        platform: CommandPalettePlatform = .current
    ) -> Self {
        let isTouchCompact = platform == .iOS && horizontalSizeClass == .compact
        return Self(
            showsEscapeKey: !isTouchCompact,
            showsCommandShortcuts: !isTouchCompact,
            showsKeyboardFooter: !isTouchCompact
        )
    }
}
