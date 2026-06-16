import Foundation
import NexusAI
import Testing

@testable import NexusMeetings

@Test func summaryStageReturnsMarkdownFromRouter() async throws {
    let router = StubMeetingSummaryRouter(text: "## TL;DR\nKrótko o standupie.")
    let stage = SummaryStage(router: router)

    let summary = try await stage.run(
        transcript: "[00:00:00] Me\nCześć\n",
        title: "Daily",
        durationSec: 600,
        customTemplate: nil
    )

    #expect(summary.contains("TL;DR"))
}

@Test func summaryStageRoutesGenerateRequestWithSafeDefaults() async throws {
    let router = StubMeetingSummaryRouter(text: "## TL;DR\nDone.")
    let stage = SummaryStage(router: router)

    _ = try await stage.run(
        transcript: "[00:00:00] Me\nCześć\n",
        title: "Daily",
        durationSec: 600,
        customTemplate: nil
    )

    let request = try #require(await router.capturedRequest)
    #expect(request.prompt.contains("Daily"))
    #expect(request.prompt.contains("Cześć"))
    #expect(request.capability == .generate)
    #expect(request.connectivity == .offlineOnly)
    #expect(request.cost == .free)
    #expect(request.providerPreference == .auto)
}

@Test func summaryStageRoutesAssistantModelProviderPreference() async throws {
    let router = StubMeetingSummaryRouter(text: "## TL;DR\nDone.")
    let stage = SummaryStage(router: router)

    _ = try await stage.run(
        transcript: "[00:00:00] Me\nCześć\n",
        title: "Daily",
        durationSec: 600,
        customTemplate: nil,
        providerPreference: .assistantModel
    )

    let request = try #require(await router.capturedRequest)
    #expect(request.providerPreference == .auto)
}

@Test func summaryStageReturnsEmptySummaryWhenProviderDisabled() async throws {
    let router = StubMeetingSummaryRouter(text: "## TL;DR\nShould not route.")
    let stage = SummaryStage(router: router)

    let summary = try await stage.run(
        transcript: "[00:00:00] Me\nCześć\n",
        title: "Daily",
        durationSec: 600,
        customTemplate: nil,
        providerPreference: .disabled
    )

    #expect(summary.isEmpty)
    #expect(await router.routeCount == 0)
}

private actor StubMeetingSummaryRouter: MeetingProcessingRouting {
    private let text: String
    private(set) var capturedRequest: AIRequest?
    private(set) var routeCount = 0

    init(text: String) {
        self.text = text
    }

    func route(_ request: AIRequest) async throws -> AIResponse {
        routeCount += 1
        capturedRequest = request
        return AIResponse(text: text, providerUsed: .appleIntelligence)
    }
}
