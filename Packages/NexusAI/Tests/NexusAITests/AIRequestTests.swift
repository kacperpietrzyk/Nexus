import Foundation
import Testing

@testable import NexusAI

@Test func connectivityPreference_isCodable() throws {
    let p: [ConnectivityPreference] = [.offlineOnly, .cloudAllowed]
    let data = try JSONEncoder().encode(p)
    let decoded = try JSONDecoder().decode([ConnectivityPreference].self, from: data)
    #expect(decoded == p)
}

@Test func costPreference_isCodable() throws {
    let p: [CostPreference] = [.free, .anyPaid]
    let data = try JSONEncoder().encode(p)
    let decoded = try JSONDecoder().decode([CostPreference].self, from: data)
    #expect(decoded == p)
}

@Test func providerPreference_isCodable() throws {
    let p: [ProviderPreference] = [.auto]
    let data = try JSONEncoder().encode(p)
    let decoded = try JSONDecoder().decode([ProviderPreference].self, from: data)
    #expect(decoded == p)
}

@Test func aiRequest_default_isOfflineOnly_freeAuto() {
    let req = AIRequest(prompt: "hello", capability: .generate)
    #expect(req.connectivity == .offlineOnly)
    #expect(req.cost == .free)
    #expect(req.providerPreference == .auto)
    #expect(req.context.isEmpty)
    #expect(req.attachments.isEmpty)
}

@Test func aiRequest_allowsCloud_isFalseWhenOfflineOnly() {
    let req = AIRequest(prompt: "hi", capability: .generate)
    #expect(req.allowsCloud == false)
}

@Test func aiRequest_allowsCloud_isTrueWhenCloudAllowed() {
    let req = AIRequest(prompt: "hi", capability: .generate, connectivity: .cloudAllowed)
    #expect(req.allowsCloud == true)
}

@Test func aiRequest_isCodable_roundTrip() throws {
    let req = AIRequest(
        prompt: "summarize",
        capability: .longContext,
        connectivity: .cloudAllowed,
        cost: .anyPaid,
        providerPreference: .auto,
        context: ["docID-1", "docID-2"],
        attachments: ["data:image/png;base64,cG5n"]
    )
    let data = try JSONEncoder().encode(req)
    let back = try JSONDecoder().decode(AIRequest.self, from: data)
    #expect(back == req)
}

@Test func aiRequest_structuredFields_defaultToNil() {
    let req = AIRequest(prompt: "hi", capability: .generate)
    #expect(req.messages == nil)
    #expect(req.tools == nil)
    #expect(req.systemPrompt == nil)
}

@Test func aiRequest_isCodable_roundTrip_withStructuredFields() throws {
    let req = AIRequest(
        prompt: "add buy milk",
        capability: .generate,
        messages: [
            AIChatMessage(role: .system, text: "You are a productivity assistant."),
            AIChatMessage(role: .user, text: "Add buy milk"),
            AIChatMessage(
                role: .tool,
                text: "{\"ok\":true}",
                toolName: "tasks.create",
                toolCallID: "call-1"
            ),
        ],
        tools: [
            AIToolSpec(
                name: "tasks.create",
                description: "Create a new task",
                parametersJSONSchema: #"{"type":"object","properties":{"title":{"type":"string"}}}"#
            )
        ],
        systemPrompt: "System block."
    )
    let data = try JSONEncoder().encode(req)
    let back = try JSONDecoder().decode(AIRequest.self, from: data)
    #expect(back == req)
    #expect(back.messages?.count == 3)
    #expect(back.tools?.first?.name == "tasks.create")
    #expect(back.systemPrompt == "System block.")
}

@Test func aiRequest_decodesLegacyPayloadWithoutStructuredKeys() throws {
    let json = """
        {
          "prompt": "summarize",
          "capability": "generate",
          "connectivity": "offlineOnly",
          "cost": "free",
          "providerPreference": "auto",
          "context": [],
          "attachments": []
        }
        """

    let req = try JSONDecoder().decode(AIRequest.self, from: Data(json.utf8))

    #expect(req.prompt == "summarize")
    #expect(req.messages == nil)
    #expect(req.tools == nil)
    #expect(req.systemPrompt == nil)
}
