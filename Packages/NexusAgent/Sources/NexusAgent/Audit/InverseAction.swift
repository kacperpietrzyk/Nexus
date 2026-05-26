import Foundation

public struct InverseAction: Codable, Equatable, Sendable {
    public let toolName: String
    public let inputJSON: Data

    public init(toolName: String, inputJSON: Data) {
        self.toolName = toolName
        self.inputJSON = inputJSON
    }
}
