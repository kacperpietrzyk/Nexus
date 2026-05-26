import Foundation

public struct ErrorDTO: Codable, Sendable, Equatable {
    public let code: Int
    public let name: String
    public let message: String

    public init(code: Int, name: String, message: String) {
        self.code = code
        self.name = name
        self.message = message
    }

    public init(from error: AgentError) {
        self.init(code: error.jsonRPCCode, name: error.name, message: error.message)
    }
}
