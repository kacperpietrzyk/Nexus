import SwiftUI

/// Row hover wash — `docs/09_SWIFTUI_IMPLEMENTATION_GUIDE.md` §Hover: no scale
/// for dense lists, just a subtle fill.
private let taskRowHoverFill = Color.white.opacity(0.04)
/// Drop-zone targeted fill — `docs/03_COMPONENTS.md` §Empty / Drop Zone:
/// "hover while dragging: border accent primary, fill primary 8%".
private let dropZoneTargetedOpacity = 0.08

/// Event kind for agenda/calendar blocks, mapping to the `DS.ColorToken.event*`
/// fill/stroke pairs (`docs/03_COMPONENTS.md` §AgendaEventBlock).
public enum LiquidEventKind: Sendable, CaseIterable {
    case focus
    case meeting
    case project
    case personal
    case admin

    /// Translucent block fill.
    public var fill: Color {
        switch self {
        case .focus: return DS.ColorToken.eventFocusFill
        case .meeting: return DS.ColorToken.eventMeetingFill
        case .project: return DS.ColorToken.eventProjectFill
        case .personal: return DS.ColorToken.eventPersonalFill
        case .admin: return DS.ColorToken.eventAdminFill
        }
    }

    /// Block border.
    public var stroke: Color {
        switch self {
        case .focus: return DS.ColorToken.eventFocusStroke
        case .meeting: return DS.ColorToken.eventMeetingStroke
        case .project: return DS.ColorToken.eventProjectStroke
        case .personal: return DS.ColorToken.eventPersonalStroke
        case .admin: return DS.ColorToken.eventAdminStroke
        }
    }

    /// Opaque accent for the leading capsule line.
    public var accent: Color {
        switch self {
        case .focus: return DS.ColorToken.accentBlue
        case .meeting: return DS.ColorToken.accentPurple
        case .project: return DS.ColorToken.accentAmber
        case .personal: return DS.ColorToken.accentGreen
        case .admin: return DS.ColorToken.statusNeutral
        }
    }
}

/// Task list row per `docs/03_COMPONENTS.md` §TaskRow.
///
/// 14 pt circle checkbox, title (struck through when done), optional accessory
/// slot (typically a ``LiquidPill`` tag), and trailing metadata text. ~32 pt
/// tall with a subtle hover wash on macOS.
public struct LiquidTaskRow<Accessory: View>: View {

    public let title: String
    public let isDone: Bool
    public let metadata: String?
    public let onToggle: () -> Void
    @ViewBuilder public var accessory: () -> Accessory

    @State private var hovering = false

    public init(
        _ title: String,
        isDone: Bool = false,
        metadata: String? = nil,
        onToggle: @escaping () -> Void = {},
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.title = title
        self.isDone = isDone
        self.metadata = metadata
        self.onToggle = onToggle
        self.accessory = accessory
    }

    public var body: some View {
        HStack(spacing: DS.Space.s) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .stroke(isDone ? DS.ColorToken.accentPrimary : DS.ColorToken.textTertiary, lineWidth: 1.5)
                    if isDone {
                        Circle()
                            .fill(DS.ColorToken.accentPrimary)
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(DS.ColorToken.textPrimary)
                    }
                }
                .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDone ? "Mark as not done" : "Mark as done")

            Text(title)
                .font(DS.FontToken.body)
                .strikethrough(isDone)
                .foregroundStyle(isDone ? DS.ColorToken.textSecondary : DS.ColorToken.textPrimary)
                .lineLimit(1)

            accessory()

            Spacer(minLength: DS.Space.s)

            if let metadata {
                Text(metadata)
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, DS.Space.s)
        .frame(minHeight: 32)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                .fill(hovering ? taskRowHoverFill : .clear)
        }
        #if os(macOS)
        .onHover { value in
            withAnimation(DS.Motion.hover) { hovering = value }
        }
        #endif
    }
}

extension LiquidTaskRow where Accessory == EmptyView {
    /// Task row without a tag accessory.
    public init(
        _ title: String,
        isDone: Bool = false,
        metadata: String? = nil,
        onToggle: @escaping () -> Void = {}
    ) {
        self.init(title, isDone: isDone, metadata: metadata, onToggle: onToggle, accessory: { EmptyView() })
    }
}

/// Agenda timeline block per `docs/03_COMPONENTS.md` §AgendaEventBlock.
///
/// Leading 3 pt accent capsule, 13 pt semibold title, 11 pt secondary
/// subtitle, on an event-tinted glass block.
public struct LiquidAgendaBlock: View {

    public let title: String
    public let subtitle: String?
    public let kind: LiquidEventKind

    public init(_ title: String, subtitle: String? = nil, kind: LiquidEventKind) {
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
    }

    public var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s) {
            Capsule(style: .continuous)
                .fill(kind.accent)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.FontToken.bodyStrong)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(DS.Space.s)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                .fill(kind.fill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                .stroke(kind.stroke, lineWidth: 1)
        }
    }
}

/// Centered empty state with an optional single CTA slot.
public struct LiquidEmptyState<Actions: View>: View {

    public let systemImage: String
    public let message: String
    @ViewBuilder public var actions: () -> Actions

    public init(systemImage: String, message: String, @ViewBuilder actions: @escaping () -> Actions) {
        self.systemImage = systemImage
        self.message = message
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: DS.Space.m) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(DS.ColorToken.textMuted)

            Text(message)
                .font(DS.FontToken.metadata)
                .foregroundStyle(DS.ColorToken.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)

            actions()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.xxl)
    }
}

extension LiquidEmptyState where Actions == EmptyView {
    /// Empty state without a CTA.
    public init(systemImage: String, message: String) {
        self.init(systemImage: systemImage, message: message, actions: { EmptyView() })
    }
}

/// Drag-and-drop target per `docs/03_COMPONENTS.md` §Empty / Drop Zone.
///
/// Dashed border, centered icon + title. While a drag hovers
/// (`isTargeted == true`) the border and fill switch to the primary accent.
/// Spec radius is 14 pt; `DS.Radius.m` (12 pt) is the closest token and is
/// used instead of a one-off constant.
public struct LiquidDropZone: View {

    public let systemImage: String
    public let title: String
    public let isTargeted: Bool

    public init(systemImage: String, title: String, isTargeted: Bool = false) {
        self.systemImage = systemImage
        self.title = title
        self.isTargeted = isTargeted
    }

    public var body: some View {
        VStack(spacing: DS.Space.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isTargeted ? DS.ColorToken.accentPrimary : DS.ColorToken.textMuted)

            Text(title)
                .font(DS.FontToken.metadata)
                .foregroundStyle(isTargeted ? DS.ColorToken.textPrimary : DS.ColorToken.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.l)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                .fill(isTargeted ? DS.ColorToken.accentPrimary.opacity(dropZoneTargetedOpacity) : .clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                .stroke(
                    isTargeted ? DS.ColorToken.accentPrimary : DS.ColorToken.strokeDefault,
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        }
        .animation(DS.Motion.hover, value: isTargeted)
    }
}
