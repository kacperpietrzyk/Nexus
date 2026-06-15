import Foundation

public enum OutputContractError: Error, Equatable {
    case invalid(reason: String)
}

public struct OutputContract<Output: Sendable & Equatable>: Sendable {
    public let schemaDescription: String  // injected into the prompt
    public let decode: @Sendable (String) throws -> Output  // throws OutputContractError on bad output
    public init(
        schemaDescription: String,
        decode: @escaping @Sendable (String) throws -> Output
    ) {
        self.schemaDescription = schemaDescription
        self.decode = decode
    }
}

public struct AssistantSkill<Output: Sendable & Equatable>: Sendable {
    public let id: String
    public let systemPrompt: String
    public let toolNames: [String]
    public let contextRecipe: ContextRecipe
    public let output: OutputContract<Output>
    public let maxIterations: Int
    public let allowsToolCalling: Bool
    public init(
        id: String,
        systemPrompt: String,
        toolNames: [String] = [],
        contextRecipe: ContextRecipe,
        output: OutputContract<Output>,
        maxIterations: Int = 1,
        allowsToolCalling: Bool = false
    ) {
        self.id = id
        self.systemPrompt = systemPrompt
        self.toolNames = toolNames
        self.contextRecipe = contextRecipe
        self.output = output
        self.maxIterations = maxIterations
        self.allowsToolCalling = allowsToolCalling
    }
}
