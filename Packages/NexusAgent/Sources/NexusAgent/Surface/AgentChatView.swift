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

    // Status notice (iOS): the agent's on-device brain is an MLX chat model that Nexus
    // downloads and assigns automatically — there is no manual download control, so this
    // banner must NOT instruct the user to download anything. Until that model is
    // assigned and on disk the probe reports it as unavailable and every turn would fail
    // silently; the banner explains that the model is being prepared automatically and
    // that its readiness is shown in Settings. Hidden when no availability probe was
    // injected (Mac / tests), so it never renders there.
    @ViewBuilder private var modelUnavailableBanner: some View {
        if !viewModel.isChatModelAvailable {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.statusWarning)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text("On-device model not ready yet")
                        .font(DS.FontToken.bodyStrong)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                    Text(
                        "Nexus prepares the on-device AI model automatically. "
                            + "Its readiness is shown in Settings under Assistant models."
                    )
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(DS.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(.strong, radius: DS.Radius.m)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Omitted-as-unit until the first §10-reachable tool call lands:
            // a floating "No activity" glass box over an empty canvas reads
            // as orphaned chrome, not as a calm empty state.
            if let rows = recentToolRows, !rows.isEmpty {
                railPanel(rows)
                    .padding(.top, 20)
                    .padding(.trailing, 26)
            }
        }
    }

    @ViewBuilder
    private var mainPane: some View {
        if viewModel.currentThreadID == nil {
            // Fresh-thread invitation, vertically centered in the content area.
            // `AgentEmptyStateView` self-centers (`maxWidth: 380` then
            // `maxWidth/maxHeight: .infinity`). The prior `.padding(.top, 160)`
            // + `height: 480` were carried 1:1 from the removed Lab oracle
            // canvas and floated "Ask Nexus" below optical center on the tall
            // Mac window.
            AgentEmptyStateView { sample in
                viewModel.createThread(title: sample)
            }
        } else {
            // The stream is top-anchored with a small breathing inset so the
            // history fills the full available height. (The prior 160 pt top
            // inset — carried 1:1 from the removed Lab oracle canvas — left a
            // ~quarter-height empty band at the top, so the conversation only
            // occupied the lower ~3/4 of the pane.)
            messageList
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.top, 20)
        }
    }

    // The oracle's flat block stream, derived purely from the already-loaded
    // `messages` (§1b / §11 — `AgentMessageGrouping`, no new query). `blocks`
    // is computed in `body` so a `isThinking` toggle re-derives the trailing
    // un-closed `.tool` branch (cheap pure walk; NOT cached in `@State`).
    private var blocks: [AgentMessageBlock] {
        AgentMessageGrouping.blocks(
            from: viewModel.messages,
            isThinking: viewModel.isThinking,
            proposals: viewModel.pendingProposals
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
                    MessageBubbleView(
                        block: block,
                        onAcceptProposal: { id in
                            try? await viewModel.acceptProposal(messageID: id)
                        },
                        onRejectProposal: { id in
                            viewModel.rejectProposal(messageID: id)
                        }
                    )
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
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.textPrimary)
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
            isLoadingModel: viewModel.isLoadingModel,
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
    private func rail(_ rows: [AgentRecentToolRow]) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.ColorToken.textTertiary)
                        .frame(width: 12, height: 12)

                    // Liquid tracked-caption eyebrow (replaces the Lab-era
                    // mono uppercase), kept discoverable over the dark glass.
                    Text("Recent tools")
                        .font(DS.FontToken.caption)
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .foregroundStyle(DS.ColorToken.textTertiary)
                }

                ForEach(rows) { row in
                    toolRow(row)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func railPanel(_ rows: [AgentRecentToolRow]) -> some View {
        // Liquid re-skin (container level): the liquid glass card recipe
        // replaces the opaque Linear control→raised→panel gradient + manual
        // Line.strong stroke + raw black glow (the slab clashed inside the
        // shell's glass content column). Rail content unchanged.
        rail(rows)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(width: 374, alignment: .topLeading)
            .frame(minHeight: 134, alignment: .topLeading)
            .liquidLightCard(cornerRadius: DS.Radius.xl)
    }

    /// `nil` when there is no active thread (the rail is then omitted
    /// entirely). Otherwise the §10-reachable newest-first tool list,
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
    /// `detail` (and its fake `"·"` separator), name + age only. Tool names
    /// keep a monospaced face (they are code identifiers, not prose); inks
    /// come from DS.
    private func toolRow(_ row: AgentRecentToolRow) -> some View {
        HStack(spacing: 8) {
            Text(row.name)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(DS.ColorToken.textSecondary)
            Spacer()
            Text(row.age)
                .font(DS.FontToken.metadata)
                .monospacedDigit()
                .foregroundStyle(DS.ColorToken.textMuted)
        }
    }
}
