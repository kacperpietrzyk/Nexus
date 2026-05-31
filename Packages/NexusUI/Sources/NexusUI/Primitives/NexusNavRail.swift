#if !os(watchOS)
import SwiftUI

public struct NexusNavRailItem<ID: Hashable>: Identifiable, @unchecked Sendable {
    public let id: ID
    public let systemImage: String
    public let label: String
    public let count: Int?

    public init(id: ID, systemImage: String, label: String, count: Int? = nil) {
        self.id = id
        self.systemImage = systemImage
        self.label = label
        self.count = count
    }
}

public struct NexusNavRail<ID: Hashable, Avatar: View>: View {
    internal static var railWidth: CGFloat { 54 }
    internal static var logoSize: CGFloat { 32 }
    internal static var buttonWidth: CGFloat { 34 }
    internal static var buttonHeight: CGFloat { 34 }

    public let items: [NexusNavRailItem<ID>]
    @Binding public var active: ID
    public let logoTitle: String
    public let avatar: Avatar?
    public let onSelect: (ID) -> Void

    // Bottom-pinned item — rendered after the Spacer so it is visually
    // anchored to the rail's bottom, matching the `LabIconRail` oracle's
    // explicit `gearshape` pin (`Spacer()` → `LabRailIcon(gearshape)` with
    // `.padding(.bottom, 18)`). Here we use `.padding(.bottom, 6)` because the
    // VStack carries `.padding(.vertical, 12)` that the oracle VStack lacks;
    // 6 + 12 = 18, exact parity. Additive + frozen-API-safe: defaults to `nil`
    // so every existing call site remains byte-for-byte unchanged.
    public let bottomItem: NexusNavRailItem<ID>?

    // One shared selection highlight glides between options when `active`
    // changes inside `withAnimation(NexusMotion.nav)` (LabKit `LabIconRail`
    // idiom). Declared once at the parent; `navButton` captures it. A static
    // single render shows it once with nothing to slide — correct.
    @Namespace private var sel

    // Audit C3: an externally-owned namespace, injected by a STABLE ancestor
    // (the Mac `ContentView`, which does not rebuild when the shell
    // re-specializes between Inbox/Agent/other). When provided it overrides
    // the internal `sel` for the selection-pill `matchedGeometryEffect`, so
    // the pill SLIDES across a full `NexusShell` re-specialization instead
    // of snapping (the old A11 trade-off — obsoleted here without AnyView
    // erasure). Additive + frozen-API-safe: defaults to `nil` so every
    // existing call site (and the internal-`sel` behaviour) is byte-for-byte
    // unchanged — the same additive-optional precedent as `bottomItem`.
    public let selectionNamespace: Namespace.ID?

    /// The namespace the selection pill's `matchedGeometryEffect` binds to:
    /// the injected stable one when present, else the internal `@Namespace`.
    private var pillNamespace: Namespace.ID { selectionNamespace ?? sel }

    // Audit C2 (user-authorised look change to this frozen MP-1 primitive):
    // the rail row under the cursor gets a faint highlight so the widened
    // A2 hit band is discoverable and the rail "reacts on the highlighted
    // area" as the user asked. Matches the established `nexusRowHover`
    // vocab (`Text.primary.opacity(0.04)`, easeOut 0.15) but is inlined —
    // `nexusRowHover()` injects `.padding(.horizontal, 8)` which would
    // break the frozen 54/34 rail metrics.
    @State private var hoveredID: ID?

    public init(
        items: [NexusNavRailItem<ID>],
        active: Binding<ID>,
        logoTitle: String = "N",
        bottomItem: NexusNavRailItem<ID>? = nil,
        selectionNamespace: Namespace.ID? = nil,
        @ViewBuilder avatar: () -> Avatar,
        onSelect: @escaping (ID) -> Void = { _ in }
    ) {
        self.items = items
        self._active = active
        self.logoTitle = logoTitle
        self.bottomItem = bottomItem
        self.selectionNamespace = selectionNamespace
        self.avatar = avatar()
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: 4) {
            logoTile

            Spacer().frame(height: 14)

            ForEach(items) { item in
                navButton(for: item)
            }

            Spacer(minLength: 0)

            // Bottom-pinned item rendered after the Spacer (oracle pattern).
            if let bottomItem {
                navButton(for: bottomItem)
                    // 6 here + the VStack's outer .padding(.vertical, 12) == the oracle's 18pt bottom inset
                    // (the oracle VStack has no outer vertical padding, so it uses .padding(.bottom, 18) directly).
                    .padding(.bottom, 6)
            }

            if let avatar {
                avatar
            }
        }
        .padding(.vertical, 12)
        .frame(width: Self.railWidth)
        .frame(maxHeight: .infinity)
        .background(NexusColor.Background.panel)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(NexusColor.Line.hairline)
                .frame(width: 1)
        }
    }

    // Logo tile — a 32pt letter square with weight `.black` + monospaced
    // design. Intentionally NOT the 5pt suppression dot from `LabIconRail`:
    // the oracle's dot was a design-time placeholder; this is a real shipped
    // app frame where the first letter of `logoTitle` acts as an identity
    // brand mark. The `logoTitle` param (default "N", call site uses "Nexus")
    // is frozen API. Do NOT regress to a dot.
    private var logoTile: some View {
        Text(String(logoTitle.prefix(1)).uppercased())
            .font(.system(size: 15, weight: .black, design: .monospaced))
            .foregroundStyle(NexusColor.Text.primary)
            .frame(width: Self.logoSize, height: Self.logoSize)
            .background(
                NexusColor.Background.raised,
                in: RoundedRectangle(cornerRadius: NexusRadius.r1, style: .continuous)
            )
            .accessibilityLabel(logoTitle)
    }

    private func navButton(for item: NexusNavRailItem<ID>) -> some View {
        let isActive = item.id == active
        return Button {
            withAnimation(NexusMotion.nav) { active = item.id }
            onSelect(item.id)
        } label: {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    if hoveredID == item.id, !isActive {
                        // Hover preview at the SAME 34×34 footprint the glyph
                        // occupies, so hovering shows where selection would
                        // land. Neutral only (never lime), tag radius to match
                        // the tight Linear item shape. No matchedGeometryEffect
                        // — only the active lime bar slides; this is a plain
                        // fade. Audit C2.
                        RoundedRectangle(cornerRadius: NexusRadius.tag)
                            .fill(NexusColor.Text.primary.opacity(0.04))
                    }
                    if isActive {
                        // Linear active indicator: a single leading neon-lime
                        // bar — the ONE lime element on this component (lime
                        // economy). It carries the `matchedGeometryEffect`
                        // (id unchanged) so it GLIDES vertically between active
                        // items, including across a `NexusShell`
                        // re-specialization when an external `selectionNamespace`
                        // is injected (the C3 contract the param exists for).
                        // Leading-aligned inside the centered glyph footprint so
                        // it does not disturb the 34×34 metrics or the 54pt hit
                        // band below.
                        Capsule()
                            .fill(NexusColor.Accent.lime)
                            .frame(width: 2.5, height: 18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .matchedGeometryEffect(id: "nexusRailSelection", in: pillNamespace)
                    }
                    Image(systemName: item.systemImage)
                        .font(.system(size: 14, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? NexusColor.Text.primary : NexusColor.Text.tertiary)
                }
                .frame(width: Self.buttonWidth, height: Self.buttonHeight)

                if let count = item.count, count > 0 {
                    countBadge(count)
                }
            }
            // The 34×34 glyph/highlight + topTrailing-anchored badge above are
            // byte-for-byte unchanged (frozen MP-1 look). This frame only
            // widens the *hit target* to the full 54pt rail band and makes the
            // whole band tappable — previously only the 34pt glyph was
            // clickable inside a 54pt rail, so a tap in the ~10pt dead margin
            // each side missed. Content stays centered (the rail already
            // centred it), so zero pixels move. Audit A2.
            .frame(width: Self.railWidth, height: Self.buttonHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                if hovering {
                    hoveredID = item.id
                } else if hoveredID == item.id {
                    hoveredID = nil
                }
            }
        }
        .help(item.label)
        .accessibilityLabel(item.label)
    }

    private func countBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(NexusType.mono)
            .monospacedDigit()
            .foregroundStyle(NexusColor.Text.tertiary)
            .padding(.horizontal, 3.5)
            .padding(.vertical, 1)
            .background(
                NexusColor.Line.strong,
                in: RoundedRectangle(cornerRadius: NexusRadius.badge, style: .continuous)
            )
            .offset(x: 5, y: -1)
            .accessibilityLabel("\(count)")
    }
}

extension NexusNavRail where Avatar == EmptyView {
    public init(
        items: [NexusNavRailItem<ID>],
        active: Binding<ID>,
        logoTitle: String = "N",
        bottomItem: NexusNavRailItem<ID>? = nil,
        selectionNamespace: Namespace.ID? = nil,
        onSelect: @escaping (ID) -> Void = { _ in }
    ) {
        self.items = items
        self._active = active
        self.logoTitle = logoTitle
        self.bottomItem = bottomItem
        self.selectionNamespace = selectionNamespace
        self.avatar = nil
        self.onSelect = onSelect
    }
}
#endif
