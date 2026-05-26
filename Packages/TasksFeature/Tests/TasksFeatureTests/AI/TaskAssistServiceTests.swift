import Foundation
import NexusAI
import NexusCore
import Testing

@testable import TasksFeature

@MainActor
struct TaskAssistServiceTests {
    @Test("refine returns trimmed provider text")
    func refineReturnsTrimmedText() async throws {
        let service = TaskAssistService(router: makeRouter(responseText: "  Improved title  "))
        let task = TaskItem(title: "draft sloppy")

        let result = try await service.run(.refine(field: .title), on: task)

        guard case .refinedText(let text) = result else {
            Issue.record("Expected refinedText result")
            return
        }
        #expect(text == "Improved title")
    }

    @Test("title refine throws typed error for empty output")
    func refineTitleThrowsOnEmptyText() async {
        let service = TaskAssistService(router: makeRouter(responseText: "   \n  "))
        let task = TaskItem(title: "draft sloppy")

        do {
            _ = try await service.run(.refine(field: .title), on: task)
            Issue.record("Expected emptyRefinement error")
        } catch TaskAssistService.AssistError.emptyRefinement(.title) {
        } catch {
            Issue.record("Expected emptyRefinement(.title), got \(error)")
        }
    }

    @Test("breakdown strips simple bullets and ignores blanks")
    func breakdownParsesLines() async throws {
        let service = TaskAssistService(
            router: makeRouter(
                responseText: """
                    - First subtask
                    2. Second subtask

                    * Third subtask
                    """
            )
        )
        let task = TaskItem(title: "Big task")

        let result = try await service.run(.breakIntoSubtasks(maxCount: 5), on: task)

        guard case .subtaskTitles(let titles) = result else {
            Issue.record("Expected subtaskTitles result")
            return
        }
        #expect(titles == ["First subtask", "Second subtask", "Third subtask"])
    }

    @Test("suggest due date parses ISO8601 response")
    func suggestDueParsesISO8601() async throws {
        let service = TaskAssistService(router: makeRouter(responseText: "2026-06-15T10:00:00Z"))
        let task = TaskItem(title: "Plan offsite")
        let now = try #require(ISO8601DateFormatter().date(from: "2026-05-11T12:00:00Z"))

        let result = try await service.run(.suggestDueDate(now: now), on: task)

        guard case .dueDate(let date) = result else {
            Issue.record("Expected dueDate result")
            return
        }
        #expect(ISO8601DateFormatter().string(from: date) == "2026-06-15T10:00:00Z")
    }

    @Test("suggest due date throws typed error on garbage")
    func suggestDueThrowsOnGarbage() async throws {
        let service = TaskAssistService(router: makeRouter(responseText: "sometime next week"))
        let task = TaskItem(title: "Plan offsite")
        let now = try #require(ISO8601DateFormatter().date(from: "2026-05-11T12:00:00Z"))

        await #expect(throws: TaskAssistService.AssistError.self) {
            _ = try await service.run(.suggestDueDate(now: now), on: task)
        }
    }

    @Test("suggest due date throws typed error for past response")
    func suggestDueThrowsOnPastDate() async throws {
        let service = TaskAssistService(router: makeRouter(responseText: "2026-05-10T12:00:00Z"))
        let task = TaskItem(title: "Plan offsite")
        let now = try #require(ISO8601DateFormatter().date(from: "2026-05-11T12:00:00Z"))

        do {
            _ = try await service.run(.suggestDueDate(now: now), on: task)
            Issue.record("Expected pastDueDate error")
        } catch TaskAssistService.AssistError.pastDueDate(let date, let thrownNow) {
            #expect(ISO8601DateFormatter().string(from: date) == "2026-05-10T12:00:00Z")
            #expect(thrownNow == now)
        } catch {
            Issue.record("Expected pastDueDate, got \(error)")
        }
    }

    @Test("requests use safe router defaults")
    func requestUsesSafeDefaults() async throws {
        let provider = CapturingAIProvider(responseText: "Improved title")
        let service = TaskAssistService(router: makeRouter(provider: provider))
        let task = TaskItem(title: "draft sloppy")

        _ = try await service.run(.refine(field: .title), on: task)

        let request = try #require(provider.capturedRequest)
        #expect(request.capability == .generate)
        #expect(request.connectivity == .offlineOnly)
        #expect(request.cost == .free)
        #expect(request.providerPreference == .auto)
    }

    @Test("offline connectivity reaches local provider when Apple Intelligence is unavailable")
    func offlineConnectivityRoutesToWhisperKitWhenOnlyLocalProviderAvailable() async throws {
        let localProvider = FakeAIProvider(
            id: .whisperKit,
            capabilities: [.generate],
            sendsDataExternally: false,
            requiresNetwork: false,
            isAvailableOnThisPlatform: true,
            responseText: "Local refinement"
        )

        let router = AIRouter(
            providers: [localProvider],
            consent: InMemoryConsentStore(),
            quota: InMemoryQuotaTracker(),
            secrets: InMemorySecretStore()
        )
        let service = TaskAssistService(router: router)
        let task = TaskItem(title: "draft sloppy")

        let result = try await service.run(.refine(field: .title), on: task)

        guard case .refinedText(let text) = result else {
            Issue.record("Expected refinedText result")
            return
        }
        #expect(text == "Local refinement")
        #expect(localProvider.generateCallCount == 1)
    }

    private func makeRouter(responseText: String) -> AIRouter {
        let provider = FakeAIProvider(
            id: .appleIntelligence,
            capabilities: [.generate],
            isAvailableOnThisPlatform: true,
            responseText: responseText
        )
        return makeRouter(provider: provider)
    }

    private func makeRouter(provider: any AIProvider) -> AIRouter {
        return AIRouter(
            providers: [provider],
            consent: InMemoryConsentStore(),
            quota: InMemoryQuotaTracker(),
            secrets: InMemorySecretStore()
        )
    }
}

private final class CapturingAIProvider: AIProvider, @unchecked Sendable {
    let id: ProviderID = .appleIntelligence
    let capabilities: Set<AICapability> = [.generate]
    let sendsDataExternally = false
    let requiresNetwork = false
    let isAvailableOnThisPlatform = true

    private let responseText: String
    var capturedRequest: AIRequest?

    init(responseText: String) {
        self.responseText = responseText
    }

    func generate(_ request: AIRequest) async throws -> AIResponse {
        capturedRequest = request
        return AIResponse(text: responseText, providerUsed: id)
    }

    func transcribe(_ request: AIRequest) async throws -> AIResponse {
        capturedRequest = request
        return AIResponse(text: responseText, providerUsed: id)
    }

    func embed(_ request: AIRequest) async throws -> AIResponse {
        capturedRequest = request
        return AIResponse(text: responseText, providerUsed: id)
    }
}
