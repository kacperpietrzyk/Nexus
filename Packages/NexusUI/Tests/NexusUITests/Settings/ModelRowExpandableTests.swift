import Foundation
import Testing

@testable import NexusUI

#if !os(watchOS)

import NexusAI
import NexusCore

@Suite("ModelRowExpandable.rowState")
@MainActor
struct ModelRowExpandableTests {
    private func makeManifest(
        purpose: String = "chat",
        contextLength: Int = 32_768,
        systemPromptOverride: String? = nil
    ) -> ModelManifest {
        ModelManifest(
            id: "qwen3.5-9b-instruct-4bit",
            hfPath: "mlx-community/Qwen3.5-9B-Instruct-4bit",
            family: "qwen3.5",
            displayName: "Qwen3.5 9B Instruct",
            sizeGB: 5.2,
            recommendedRAMGB: 12,
            contextLength: contextLength,
            supportsTools: true,
            supportsVision: false,
            supportedLocales: ["en", "pl"],
            purpose: purpose,
            systemPromptOverride: systemPromptOverride
        )
    }

    @Test("chat-purpose manifest shows the slider / system-prompt block")
    func chatPurposeShowsSliders() {
        let state = ModelRowExpandable.rowState(
            manifest: makeManifest(purpose: "chat"),
            localState: ModelManifestLocalState()
        )

        #expect(state.showsChatSliders == true)
    }

    @Test("embedder-purpose manifest hides the slider / system-prompt block")
    func embedderPurposeHidesSliders() {
        let state = ModelRowExpandable.rowState(
            manifest: makeManifest(purpose: "embedder"),
            localState: ModelManifestLocalState()
        )

        #expect(state.showsChatSliders == false)
    }

    @Test("downloaded + unassigned chat yields assign-chat then re-download + delete")
    func downloadedStatusActions() {
        // Task 27b: a downloaded chat model that is not yet the active chat
        // model offers the Assign-as-Chat affordance ahead of re-download /
        // delete (primary action first). The pre-27b expectation here was
        // `[.reDownload, .delete]`; the Action set legitimately grew because
        // assign is now part of the row's decided affordances.
        let state = ModelRowExpandable.rowState(
            manifest: makeManifest(purpose: "chat"),
            localState: ModelManifestLocalState(status: .downloaded)
        )

        #expect(state.actions == [.assignChat, .reDownload, .delete])
    }

    @Test("downloaded + unassigned chat offers assignChat, never assignEmbedder")
    func downloadedChatOffersAssignChatOnly() {
        let state = ModelRowExpandable.rowState(
            manifest: makeManifest(purpose: "chat"),
            localState: ModelManifestLocalState(status: .downloaded, assignedAsChat: false)
        )

        #expect(state.actions.contains(.assignChat))
        #expect(!state.actions.contains(.assignEmbedder))
    }

    @Test("downloaded chat already assigned does not offer a redundant assignChat")
    func downloadedChatAlreadyAssignedHidesAssign() {
        let state = ModelRowExpandable.rowState(
            manifest: makeManifest(purpose: "chat"),
            localState: ModelManifestLocalState(status: .downloaded, assignedAsChat: true)
        )

        #expect(!state.actions.contains(.assignChat))
        #expect(state.actions == [.reDownload, .delete])
    }

    @Test("downloaded + unassigned embedder offers assignEmbedder, never assignChat")
    func downloadedEmbedderOffersAssignEmbedderOnly() {
        let state = ModelRowExpandable.rowState(
            manifest: makeManifest(purpose: "embedder"),
            localState: ModelManifestLocalState(status: .downloaded, assignedAsEmbedder: false)
        )

        #expect(state.actions.contains(.assignEmbedder))
        #expect(!state.actions.contains(.assignChat))
        #expect(state.actions == [.assignEmbedder, .reDownload, .delete])
    }

    @Test("downloaded embedder already assigned does not offer a redundant assignEmbedder")
    func downloadedEmbedderAlreadyAssignedHidesAssign() {
        let state = ModelRowExpandable.rowState(
            manifest: makeManifest(purpose: "embedder"),
            localState: ModelManifestLocalState(status: .downloaded, assignedAsEmbedder: true)
        )

        #expect(!state.actions.contains(.assignEmbedder))
        #expect(state.actions == [.reDownload, .delete])
    }

    @Test("not-downloaded model offers no assign actions regardless of purpose")
    func notDownloadedOffersNoAssign() {
        let availableChat = ModelRowExpandable.rowState(
            manifest: makeManifest(purpose: "chat"),
            localState: ModelManifestLocalState(status: .available)
        )
        let downloadingEmbedder = ModelRowExpandable.rowState(
            manifest: makeManifest(purpose: "embedder"),
            localState: ModelManifestLocalState(status: .downloading)
        )

        #expect(!availableChat.actions.contains(.assignChat))
        #expect(!availableChat.actions.contains(.assignEmbedder))
        #expect(availableChat.actions == [.download])
        #expect(!downloadingEmbedder.actions.contains(.assignEmbedder))
        // A live download renders progress, not a button — no actions at all.
        #expect(downloadingEmbedder.actions == [])
    }

    @Test("available status yields a single download action")
    func availableStatusActions() {
        let state = ModelRowExpandable.rowState(
            manifest: makeManifest(),
            localState: ModelManifestLocalState(status: .available)
        )

        #expect(state.actions == [.download])
    }

    @Test("downloading shows progress (no button); error offers retry download")
    func downloadingShowsProgressErrorRetries() {
        let downloading = ModelRowExpandable.rowState(
            manifest: makeManifest(),
            localState: ModelManifestLocalState(status: .downloading)
        )
        let errored = ModelRowExpandable.rowState(
            manifest: makeManifest(),
            localState: ModelManifestLocalState(status: .error)
        )

        // In-flight: a progress indicator replaces the button, so a second tap
        // can't spawn a racing worker.
        #expect(downloading.actions == [])
        #expect(downloading.showsProgress == true)
        // Failed: retry is offered (the reason is surfaced separately).
        #expect(errored.actions == [.download])
        #expect(errored.showsProgress == false)
    }

    @Test("available and downloaded never show the progress indicator")
    func nonDownloadingHidesProgress() {
        let available = ModelRowExpandable.rowState(
            manifest: makeManifest(),
            localState: ModelManifestLocalState(status: .available)
        )
        let downloaded = ModelRowExpandable.rowState(
            manifest: makeManifest(),
            localState: ModelManifestLocalState(status: .downloaded)
        )

        #expect(available.showsProgress == false)
        #expect(downloaded.showsProgress == false)
    }

    @Test("nil systemPromptOverride labels as default")
    func systemPromptLabelDefault() {
        let state = ModelRowExpandable.rowState(
            manifest: makeManifest(systemPromptOverride: nil),
            localState: ModelManifestLocalState()
        )

        #expect(state.systemPromptLabel == "default")
    }

    @Test("non-nil systemPromptOverride labels as custom")
    func systemPromptLabelCustom() {
        let state = ModelRowExpandable.rowState(
            manifest: makeManifest(systemPromptOverride: "Be terse."),
            localState: ModelManifestLocalState()
        )

        #expect(state.systemPromptLabel == "custom")
    }

    @Test("tags reflect chat / embed assignment flags")
    func tagsReflectAssignment() {
        let none = ModelRowExpandable.rowState(
            manifest: makeManifest(),
            localState: ModelManifestLocalState(assignedAsChat: false, assignedAsEmbedder: false)
        )
        let chatOnly = ModelRowExpandable.rowState(
            manifest: makeManifest(),
            localState: ModelManifestLocalState(assignedAsChat: true, assignedAsEmbedder: false)
        )
        let both = ModelRowExpandable.rowState(
            manifest: makeManifest(),
            localState: ModelManifestLocalState(assignedAsChat: true, assignedAsEmbedder: true)
        )

        #expect(none.tags == [])
        #expect(chatOnly.tags == ["CHAT"])
        #expect(both.tags == ["CHAT", "EMBED"])
    }

    @Test("max-tokens default is clamped to the context length")
    func maxTokensDefaultClampedToContext() {
        // A 2048-context model must not seed a 4096 default outside the slider range.
        let small = ModelRowExpandable.rowState(
            manifest: makeManifest(contextLength: 2048),
            localState: ModelManifestLocalState()
        )
        let large = ModelRowExpandable.rowState(
            manifest: makeManifest(contextLength: 32_768),
            localState: ModelManifestLocalState()
        )

        #expect(small.maxTokensDefault == 2048)
        #expect(large.maxTokensDefault == 4096)
    }

    @Test("max-tokens slider upper bound is clamped to at least 256")
    func maxTokensUpperBoundClamped() {
        let degenerate = ModelRowExpandable.rowState(
            manifest: makeManifest(contextLength: 0),
            localState: ModelManifestLocalState()
        )

        #expect(degenerate.maxTokensUpperBound == 256)
    }
}

#endif
