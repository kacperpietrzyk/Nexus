import NexusUI
import SwiftUI

public struct AgentChatView: View {
    @StateObject private var viewModel: AgentChatViewModel

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    public init(viewModel: @autoclosure @escaping () -> AgentChatViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    public var body: some View {
        // MP-5.1c: iOS-compact renders a single-column conversation with NO
        // rail — the IOSAgentPreview oracle's deliberate phone-vs-Mac
        // divergence ("phone is focus, not the dashboard"), the same class as
        // the IOSTodayPreview no-right-rail divergence. `regularBody` is the
        // current 2-pane body extracted BYTE-IDENTICAL: Mac + iPad-regular
        // render exactly as before (zero regression on the MP-3.2-CLOSED Mac
        // Agent surface — this byte-identity is the load-bearing invariant).
        // The iPhone TabView host has no shell bottom band, so compact mode
        // mounts its own AgentInputBar while keeping the Mac AgentBottomInput
        // flow outside this view unchanged. iPad regular-width also runs
        // inside the iOS TabView host, so it gets the same inline composer
        // under the regular two-pane body.
        #if os(iOS)
        if horizontalSizeClass == .compact {
            compactBody
        } else {
            regularBodyWithInlineInput
        }
        #else
        regularBody
        #endif
    }

    @ViewBuilder private var compactBody: some View {
        // Single column, NO rail, NO Spacer. Reuses the SAME
        // `AgentEmptyStateView`/`messageList` sub-views `regularBody` uses —
        // never forked (forking would risk regression on the shared Mac
        // path). The 2-pane-specific empty-state geometry
        // (`maxWidth 620 / height 480 / leading 26`) is left-pane geometry
        // that does not apply to a single column, so the compact empty-state
        // is `maxWidth: .infinity` instead. `messageList` is reused as-is.
        VStack(spacing: 0) {
            modelUnavailableBanner
                .padding(.horizontal, 14)
                .padding(.top, 12)

            Group {
                if viewModel.currentThreadID == nil {
                    AgentEmptyStateView { sample in
                        viewModel.createThread(title: sample)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    messageList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            compactInputBar
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
        .onAppear {
            viewModel.refreshChatModelAvailability()
            viewModel.warmChatModelIfNeeded()
        }
    }

    private var regularBodyWithInlineInput: some View {
        VStack(spacing: 0) {
            modelUnavailableBanner
                .padding(.horizontal, 18)
                .padding(.top, 12)

            regularBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            compactInputBar
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
        }
        .onAppear {
            viewModel.refreshChatModelAvailability()
            viewModel.warmChatModelIfNeeded()
        }
    }

    // Proactive nudge (iOS): the agent's on-device brain is an MLX chat model that may
    // never have been downloaded (e.g. the Welcome download step was skipped or the
    // `welcomeShown` flag was set by an earlier build). When absent, every turn fails
    // silently — this banner points the user at Settings → Manage Models. Hidden when
    // no availability probe was injected (Mac / tests), so it never renders there.
    @ViewBuilder private var modelUnavailableBanner: some View {
        if !viewModel.isChatModelAvailable {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NexusColor.Text.secondary)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text("On-device model not downloaded")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NexusColor.Text.primary)
                    Text("Nexus needs the on-device AI model to answer. Download it in Settings → Manage Models.")
                        .font(.caption2)
                        .foregroundStyle(NexusColor.Text.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NexusColor.Background.raised.opacity(0.84), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(NexusColor.Line.regular.opacity(0.9), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
        }
    }

    private var regularBody: some View {
        // MP-3.2 slice 4: the oracle 2-pane content geometry is now realized
        // (`Lab/AgentChatPreview.swift` `content:` — read-only, never
        // imported). Slices 2–3 deliberately ran SINGLE-COLUMN and deferred
        // the split + the `maxWidth: 620` message cap to this slice, because
        // committing the 300pt right rail earlier would have been the §10
        // "never fake a region whose data isn't reachable" violation — the
        // rail's content gate had not yet been adjudicated.
        //
        // That §10 ruling is now locked (advisor-decided): of the oracle
        // rail's three sections only RECENT TOOLS is §10-REACHABLE —
        // it derives purely from the already-loaded `viewModel.messages`
        // (see `AgentRecentTools`, §1b/§11, no new query). MEMORY +
        // SCHEDULES are §10-OMITTED: no memory/schedule read is reachable
        // from this surface and wiring one would be a §11 new-query/behavior
        // violation. Omitted = GONE ENTIRELY — the rail is JUST the
        // RECENT TOOLS section: no omitted headers, no empty bodies,
        // and no orphan section dividers (the oracle's inter-section rules
        // separated three sections; with one surviving section there is
        // nothing to divide). This is the established MP-3.1/MP-2 precedent.
        //
        // The 620 message-column cap + the oracle's inner content paddings
        // are now applied — the slices 2–3 deferral is fully discharged.
        //
        // Still-true wallpaper-occlusion invariant (binding since slice 3):
        // no opaque background fill on this content — the stream/empty-state
        // read transparent over the §1 shell-organism wallpaper (all text
        // uses foreground tokens; the oracle tool rows carry their own glass
        // substrate; the §5 error row uses a primary foreground token).
        HStack(alignment: .top, spacing: 0) {
            mainPane
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.top, 160)

            railPanel
                .padding(.top, 150)
                .padding(.trailing, 26)
        }
    }

    @ViewBuilder
    private var mainPane: some View {
        if viewModel.currentThreadID == nil {
            AgentEmptyStateView { sample in
                viewModel.createThread(title: sample)
            }
            .frame(maxWidth: 520)
            .frame(height: 480)
        } else {
            messageList
        }
    }

    // The oracle's flat block stream, derived purely from the already-loaded
    // `messages` (§1b / §11 — `AgentMessageGrouping`, no new query). `blocks`
    // is computed in `body` so a `isThinking` toggle re-derives the trailing
    // un-closed `.tool` branch (cheap pure walk; NOT cached in `@State`).
    private var blocks: [AgentMessageBlock] {
        AgentMessageGrouping.blocks(
            from: viewModel.messages,
            isThinking: viewModel.isThinking
        )
    }

    private var messageList: some View {
        ScrollView {
            // Oracle message column (`Lab/AgentChatPreview.swift` lines
            // 45-70): `VStack(alignment:.leading, spacing:24)` capped at
            // `maxWidth: 620` with `.padding(.leading, 26).padding(.top, 4)
            // .padding(.bottom, 24)`. The cap + the `.bottom, 24` scroll
            // breathing room were the slices 2–3 SINGLE-COLUMN deferral —
            // discharged here. The slice-3 single-column `.padding(.trailing,
            // 26)` is REMOVED: in the 2-pane the column is left-anchored and
            // capped at 620, with the `Spacer` + rail occupying the right
            // side, so a trailing inset on the column no longer applies. The
            // `.bottom, 24` is scroll-content breathing room, independent of
            // the §1c shell bottom band (which is the shell's own band below
            // the content area).
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(blocks) { block in
                    MessageBubbleView(block: block)
                }

                if let lastError = viewModel.lastError {
                    // §5: inline error row = the ScrollView translation of
                    // the canonical anchor `TaskListView.errorRow`
                    // (`Packages/TasksFeature/.../TaskListView.swift:86-95`):
                    //   Text(message).font(.caption)
                    //     .foregroundStyle(NexusColor.Text.primary)
                    //     .listRowInsets(EdgeInsets(top:8,leading:12,
                    //                               bottom:8,trailing:12))
                    // MP-2 burned the hue ("error legibility via
                    // contrast/weight, not color") — the old chromatic
                    // `Semantic.negative` was a §5 violation, now retired.
                    // The `listRowInsets` become an equivalent `.padding`
                    // in the `ScrollView`/`LazyVStack` context.
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(NexusColor.Text.primary)
                        .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.leading, 26)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        // iOS-only: swipe down over the conversation interactively dismisses the
        // keyboard. Compiled out on macOS so the shared `regularBody` Mac path
        // remains byte-identical (load-bearing invariant per `body` comment).
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
    }

    private var compactInputBar: some View {
        AgentInputBar(
            onSendWithAttachments: { text, attachments, contextPrefix in
                if viewModel.currentThreadID == nil {
                    viewModel.createThread(title: text)
                }
                return await viewModel.send(
                    userMessage: text,
                    attachments: attachments,
                    contextPrefix: contextPrefix
                )
            },
            isThinking: viewModel.isThinking,
            voiceCapture: viewModel.voiceCapture,
            imageCaptureAvailability: {
                viewModel.isImageCaptureAvailable()
            },
            imageAttachmentDeferralReason: {
                viewModel.imageAttachmentDeferralReason()
            }
        )
    }

    // MARK: - Rail (§10-gated)

    // The oracle rail (`Lab/AgentChatPreview.swift` lines 132-191) had three
    // sections; per the slice-4 §10 ruling only RECENT TOOLS survives
    // (the only one derivable from already-loaded state). MEMORY +
    // SCHEDULES are GONE ENTIRELY — no headers, no empty bodies, and no
    // orphan dividers (a lone section needs no separator).
    private var rail: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(NexusColor.Text.muted)
                        .frame(width: 12, height: 12)

                    // Oracle `eyebrow(_:)`: mono SemiBold 10 / tracking
                    // 1.8 / §2 `faint` → `Text.muted`, optically lifted here
                    // so the rail remains discoverable over the dark wallpaper.
                    Text("RECENT TOOLS")
                        .font(Font.custom("IBMPlexMono-SemiBold", size: 10))
                        .tracking(1.8)
                        .foregroundStyle(NexusColor.Text.tertiary)
                }

                if let rows = recentToolRows, !rows.isEmpty {
                    ForEach(rows) { row in
                        toolRow(row)
                    }
                } else {
                    // Oracle empty branch: meta 12 / §2 `dim` →
                    // `Text.muted`. Fires when there is no thread OR no
                    // §10-reachable tool call yet (both fall here — a thread
                    // with no tool messages must not render a blank body).
                    Text("No activity")
                        .font(NexusType.meta)
                        .foregroundStyle(NexusColor.Text.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var railPanel: some View {
        // Liquid re-skin (container level): the liquid glass card recipe
        // replaces the opaque Linear control→raised→panel gradient + manual
        // Line.strong stroke + raw black glow (the slab clashed inside the
        // shell's glass content column). Rail content unchanged.
        rail
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(width: 374, alignment: .topLeading)
            .frame(minHeight: 134, alignment: .topLeading)
            .liquidGlass(.card, radius: DS.Radius.xl)
    }

    /// `nil` when there is no active thread (the rail then shows the oracle
    /// empty branch). Otherwise the §10-reachable newest-first tool list,
    /// derived purely from the already-loaded `messages` (see
    /// `AgentRecentTools` — §1b/§11, no new query). `Date()` at body-eval is
    /// sufficient (the derivation stays pure via the injected `now`); a
    /// `TimelineView(.everyMinute)` wrapper would only keep ages live and is
    /// deliberately not added here for simplicity.
    private var recentToolRows: [AgentRecentToolRow]? {
        guard viewModel.currentThreadID != nil else { return nil }
        return AgentRecentTools.rows(from: viewModel.messages, now: Date())
    }

    /// One rail row — the oracle `tool(_:_:_:)` layout minus the §10-OMITTED
    /// `detail` (and its fake `"·"` separator), name + age only. §2:
    /// `soft → Text.tertiary` for the name, `dim → Text.disabled` for the
    /// age; both IBMPlexMono SemiBold at size 10.
    private func toolRow(_ row: AgentRecentToolRow) -> some View {
        HStack(spacing: 8) {
            Text(row.name)
                .font(Font.custom("IBMPlexMono-SemiBold", size: 10))
                .foregroundStyle(NexusColor.Text.tertiary)
            Spacer()
            Text(row.age)
                .font(NexusType.metaMono)
                .foregroundStyle(NexusColor.Text.disabled)
        }
    }
}
