import Foundation
import Testing

@testable import NexusUI

#if !os(watchOS)

import NexusAI

@Suite("DownloadModelStep.downloadPlan")
@MainActor
struct DownloadModelPlanTests {
    private func makeCatalog() -> ModelCatalog.CatalogDoc {
        // Use the real bundled catalog so the entry IDs/hfPaths stay in sync.
        // swiftlint:disable:next force_try
        try! ModelCatalog.loadDefault()
    }

    @Test("non-skip with chat + embedder selections plans chat then embedder")
    func planResolvesChatThenEmbedder() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let state = WelcomeFlowState(defaults: defaults)
        let catalog = makeCatalog()
        let chatEntry = catalog.chat.first!
        let embedderEntry = catalog.embedders.first!
        state.selectedChatModelID = chatEntry.id
        state.selectedEmbedderID = embedderEntry.id
        state.skipMLX = false

        let plan = DownloadModelStep.downloadPlan(state: state, catalog: catalog)

        #expect(plan.count == 2)
        #expect(plan[0].manifestID == chatEntry.id)
        #expect(plan[0].hfPath == chatEntry.hfPath)
        #expect(plan[0].totalBytes == Int64(chatEntry.sizeGB * 1_073_741_824))
        #expect(plan[1].manifestID == embedderEntry.id)
        #expect(plan[1].hfPath == embedderEntry.hfPath)
        #expect(plan[1].totalBytes == Int64(embedderEntry.sizeGB * 1_073_741_824))
    }

    @Test("skip path plans nothing")
    func skipPlansNothing() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let state = WelcomeFlowState(defaults: defaults)
        let catalog = makeCatalog()
        state.selectedChatModelID = catalog.chat.first!.id
        state.selectedEmbedderID = catalog.embedders.first!.id
        state.skipMLX = true

        let plan = DownloadModelStep.downloadPlan(state: state, catalog: catalog)

        #expect(plan.isEmpty)
    }

    @Test("embedder-only selection plans just the embedder")
    func embedderOnlyPlansEmbedder() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let state = WelcomeFlowState(defaults: defaults)
        let catalog = makeCatalog()
        let embedderEntry = catalog.embedders.first!
        state.selectedChatModelID = nil
        state.selectedEmbedderID = embedderEntry.id
        state.skipMLX = false

        let plan = DownloadModelStep.downloadPlan(state: state, catalog: catalog)

        #expect(plan.count == 1)
        #expect(plan[0].manifestID == embedderEntry.id)
    }

    @Test("unknown selected ID is dropped from the plan")
    func unknownIDDropped() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let state = WelcomeFlowState(defaults: defaults)
        let catalog = makeCatalog()
        state.selectedChatModelID = "definitely-not-in-catalog"
        state.selectedEmbedderID = catalog.embedders.first!.id
        state.skipMLX = false

        let plan = DownloadModelStep.downloadPlan(state: state, catalog: catalog)

        #expect(plan.count == 1)
        #expect(plan[0].manifestID == catalog.embedders.first!.id)
    }
}

#endif
