import NexusAgent
import NexusUI
import SwiftUI

// MARK: - Agent shell band content (MP-3.2 §1a top control + §1c bottom input)
//
// Extracted from `ContentView.swift` at MP-3.2 slice 2: with the new §1c
// `AgentBottomInput` added, the host file approached the §11 600-line cap, so
// the two Agent-specific band views were lifted into this sibling
// (XcodeGen `sources: [Apps/NexusMac]` globs the directory, so
// `xcodegen generate` picks it up with no `project.yml` change). Both views
// observe the SAME shared upstream `AgentChatViewModel`
// (`AgentComposition.chatViewModel`, env-injected) the host hands them, so the
// top control, the message content, and the bottom composer stay in sync.

/// §1a control-mode top-bar content for the Agent shell destination.
/// Structural 1:1 replica of the accepted Agent oracle's `LabTopBar { … }`
/// content (the LabKit oracle, since internalized into NexusUI; the `Lab/`
/// tree was deleted in MP-6), re-toned through the MP-2.2
/// §2 achromatic LabPalette→NexusColor map:
/// `soft→Text.tertiary`, `ink→Text.primary`, `faint→Text.muted`,
/// `glassRim→Line.hairline`, `dim→Text.disabled`. Not a primitive — a thin
/// token composition, same status as the private `NexusCommandBar` /
/// `InboxFilterTab`. Inter-SemiBold 13 / IBMPlexMono-Medium 11/10 are
/// below/aside the `NexusType` scale, so raw `Font.custom` against the
/// process-registered family is the honest §8 stopgap (same path
/// `NexusCommandBar` uses for its ⌘K kbd chip).
///
/// The thread label is derived from the live view-model (`threads` +
/// `currentThreadID`, both already published — no new query / behaviour):
/// `"Thread: <title>"` for a titled thread, `"Thread: current"` for the
/// untitled-default subcase, `"Thread: new"` when no thread is selected.
/// The oracle's literal `"today · May 15"` is hard-coded sample text, not a
/// format spec, so no date is rendered (§11 — no invented backend). The
/// `nowy ⌘⇧A` hint is a real affordance: `⌘⇧A` now navigates-to-Agent
/// globally, so the hint creates a new thread via the existing
/// `viewModel.createThread()` (no new behaviour).
struct AgentTopControl: View {
    @ObservedObject var viewModel: AgentChatViewModel

    private var threadLabel: String {
        guard let currentID = viewModel.currentThreadID else {
            return "New thread"
        }
        let title = viewModel.threads.first { $0.id == currentID }?.title ?? ""
        return title.isEmpty ? "Current thread" : title
    }

    var body: some View {
        // The shell wraps `topControl()` in its own `HStack(spacing: 14)`
        // (mirroring the oracle `LabTopBar`), but a `View` struct's body
        // must be a single layout container for `Spacer()` to expand and
        // for the 6 elements to lay out horizontally. This inner
        // `HStack(spacing: 14)` is byte-equivalent to the oracle: the shell's
        // outer HStack has a single child (zero inter-child spacing applies),
        // and this inner stack reproduces the oracle's spacing-14 rhythm 1:1.
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Circle()
                    .fill(NexusColor.Text.tertiary)
                    .frame(width: 5, height: 5)
                Text("Nexus")
                    .font(Font.custom("Inter-SemiBold", size: 13))
                    .foregroundStyle(NexusColor.Text.primary)
            }

            Text("ready")
                .font(Font.custom("IBMPlexMono-Medium", size: 11))
                .foregroundStyle(NexusColor.Text.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(DS.ColorToken.glassSelected, in: Capsule())
                .overlay(Capsule().strokeBorder(NexusColor.Line.hairline, lineWidth: 1))

            Spacer()

            Text(threadLabel)
                .font(Font.custom("IBMPlexMono-Medium", size: 11))
                .foregroundStyle(NexusColor.Text.muted)
                .lineLimit(1)

            Rectangle()
                .fill(NexusColor.Line.hairline)
                .frame(width: 1, height: 12)

            // Deliberate oracle deviation: an interactive affordance over the
            // oracle's static hint, wired to the existing `createThread()` —
            // recorded in counts §12 at MP-3.2 closeout.
            Button(
                action: { viewModel.createThread() },
                label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                        Text("New")
                            .font(Font.custom("Inter-SemiBold", size: 12))
                    }
                    .foregroundStyle(NexusColor.Text.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(DS.ColorToken.glassSelected, in: Capsule())
                    .overlay(Capsule().strokeBorder(NexusColor.Line.regular, lineWidth: 1))
                }
            )
            .buttonStyle(.plain)
            .accessibilityLabel("New thread")
        }
    }
}

/// §1c surface-input-mode bottom-bar content for the Agent shell
/// destination. Hosts the real `AgentInputBar` (Phase 1i-Outer
/// voice/image/file capture) unchanged — §11 forbids destroying working
/// input behind a visual reskin.
///
/// **Why `@ObservedObject` instead of reading `@Environment` directly:**
/// `@Environment` does not subscribe to `@Published` properties on a
/// reference-type value. Reading `agentChatViewModel` from env in the host
/// and passing the result into a child view with `let viewModel:` would
/// leave `isThinking` (and every other `@Published` field) stale until the
/// host re-rendered for an unrelated reason. The `@ObservedObject` wrapper
/// is the correct, intentional SwiftUI bridge: it subscribes the *wrapper
/// view* to the view model's published changes, so `isThinking` flows live
/// into `AgentInputBar`. `AgentTopControl` uses the identical pattern for
/// the same reason. Both wrappers observe the SAME upstream singleton
/// (`AgentComposition.chatViewModel`, env-injected by the host), so a
/// `send` here re-renders the message list and the "Thinking…" indicator
/// stays consistent across content and input. **This seam is intentional
/// and closed; no further tracking required.**
struct AgentBottomInput: View {
    @ObservedObject var viewModel: AgentChatViewModel

    var body: some View {
        AgentInputBar(
            onSendWithAttachments: { text, attachments, contextPrefix in
                // Mirror the iOS compact composer: with no thread selected,
                // `viewModel.send` would hit its `guard let threadID` and
                // silently no-op (no "Thinking…", nothing persisted). On a
                // fresh launch the Mac shell has no thread, so the bottom
                // input must create one before the first send.
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
}
