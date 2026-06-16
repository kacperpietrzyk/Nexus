import Foundation
import NexusAI

public protocol MeetingProcessingRouting: Sendable {
    func route(_ request: AIRequest) async throws -> AIResponse
}

extension AIRouter: MeetingProcessingRouting {}

public final class SummaryStage: Sendable {
    private let router: any MeetingProcessingRouting

    public init(router: any MeetingProcessingRouting) {
        self.router = router
    }

    public func run(
        transcript: String,
        title: String,
        durationSec: Int,
        customTemplate: String?,
        providerPreference: MeetingsSummaryProviderPreference = .assistantModel,
        screenContext: String? = nil
    ) async throws -> String {
        guard let aiProviderPreference = providerPreference.providerPreference else {
            return ""
        }

        let prompt = MeetingPromptBuilder.summaryPrompt(
            transcript: transcript,
            title: title,
            durationSec: durationSec,
            customTemplate: customTemplate,
            screenContext: screenContext
        )
        let request = AIRequest(
            prompt: prompt,
            capability: .generate,
            connectivity: .offlineOnly,
            cost: .free,
            providerPreference: aiProviderPreference
        )
        let response = try await router.route(request)
        return response.text
    }
}
