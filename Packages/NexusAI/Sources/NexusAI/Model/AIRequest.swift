import Foundation

/// Single AI call request. Routed by `AIRouter`, fulfilled by exactly one `AIProvider`.
///
/// `context` is an opaque list of identifiers (e.g. `Item.id` strings) the caller wants
/// the provider to be able to cite. The router does not interpret them; providers in
/// later phases will use them for retrieval (e.g. providers may inject them as
/// tool inputs or citeable context).
///
/// `messages`, `tools`, and `systemPrompt` are optional structured fields used by
/// providers that support native tool-calling (e.g. MLX). Providers that do not
/// support these fields ignore them and fall back to the flat `prompt` string.
public struct AIRequest: Sendable, Codable, Equatable {
    public var prompt: String
    public var capability: AICapability
    public var connectivity: ConnectivityPreference
    public var cost: CostPreference
    public var providerPreference: ProviderPreference
    public var context: [String]
    public var attachments: [String]
    public var audioURL: URL?
    /// Structured conversation history for multi-turn / tool-call providers.
    public var messages: [AIChatMessage]?
    /// Tools the model may call during this turn.
    public var tools: [AIToolSpec]?
    /// System-level instructions for providers that support a separate system prompt.
    public var systemPrompt: String?

    public init(
        prompt: String,
        capability: AICapability,
        connectivity: ConnectivityPreference = .offlineOnly,
        cost: CostPreference = .free,
        providerPreference: ProviderPreference = .auto,
        context: [String] = [],
        attachments: [String] = [],
        audioURL: URL? = nil,
        messages: [AIChatMessage]? = nil,
        tools: [AIToolSpec]? = nil,
        systemPrompt: String? = nil
    ) {
        self.prompt = prompt
        self.capability = capability
        self.connectivity = connectivity
        self.cost = cost
        self.providerPreference = providerPreference
        self.context = context
        self.attachments = attachments
        self.audioURL = audioURL
        self.messages = messages
        self.tools = tools
        self.systemPrompt = systemPrompt
    }

    /// `true` when this request is permitted to reach a cloud provider.
    /// Required gate (with consent + quota) for any provider whose `requiresNetwork == true`.
    public var allowsCloud: Bool { connectivity == .cloudAllowed }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case prompt, capability, connectivity, cost, providerPreference
        case context, attachments, audioURL
        case messages, tools, systemPrompt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        prompt = try c.decode(String.self, forKey: .prompt)
        capability = try c.decode(AICapability.self, forKey: .capability)
        connectivity = try c.decode(ConnectivityPreference.self, forKey: .connectivity)
        cost = try c.decode(CostPreference.self, forKey: .cost)
        providerPreference = try c.decode(ProviderPreference.self, forKey: .providerPreference)
        context = try c.decode([String].self, forKey: .context)
        attachments = try c.decode([String].self, forKey: .attachments)
        audioURL = try c.decodeIfPresent(URL.self, forKey: .audioURL)
        messages = try c.decodeIfPresent([AIChatMessage].self, forKey: .messages)
        tools = try c.decodeIfPresent([AIToolSpec].self, forKey: .tools)
        systemPrompt = try c.decodeIfPresent(String.self, forKey: .systemPrompt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(prompt, forKey: .prompt)
        try c.encode(capability, forKey: .capability)
        try c.encode(connectivity, forKey: .connectivity)
        try c.encode(cost, forKey: .cost)
        try c.encode(providerPreference, forKey: .providerPreference)
        try c.encode(context, forKey: .context)
        try c.encode(attachments, forKey: .attachments)
        try c.encodeIfPresent(audioURL, forKey: .audioURL)
        try c.encodeIfPresent(messages, forKey: .messages)
        try c.encodeIfPresent(tools, forKey: .tools)
        try c.encodeIfPresent(systemPrompt, forKey: .systemPrompt)
    }
}
