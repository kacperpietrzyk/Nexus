import Foundation
import NexusAgentTools
import Testing

struct AgentErrorTests {
    @Test
    func mapsErrorsToJSONRPCCodes() {
        #expect(AgentError.appNotRunning.jsonRPCCode == -32001)
        #expect(AgentError.mcpDisabled.jsonRPCCode == -32002)
        #expect(AgentError.notFound("Missing").jsonRPCCode == -32003)
        #expect(AgentError.validation("Invalid").jsonRPCCode == -32004)
        #expect(AgentError.conflict("Conflict").jsonRPCCode == -32005)
        #expect(AgentError.internalError("Boom").jsonRPCCode == -32099)
    }

    @Test
    func preservesValidationMessage() {
        let error = AgentError.validation("Title is required")

        #expect(error.name == "validation")
        #expect(error.message == "Title is required")
        #expect(AgentError.from(error.asNSError) == error)
    }

    @Test
    func convertsToNSErrorWithDomainCodeAndUserInfo() {
        let error = AgentError.conflict("Task already exists")
        let nsError = error.asNSError

        #expect(nsError.domain == AgentError.errorDomain)
        #expect(nsError.code == -32005)
        #expect(nsError.userInfo[NSLocalizedDescriptionKey] as? String == "Task already exists")
        #expect(nsError.userInfo["agent.error.name"] as? String == "conflict")
    }

    @Test
    func treatsForeignDomainErrorCodesAsInternalErrors() {
        let nsError = NSError(
            domain: "com.example.foreign",
            code: -32004,
            userInfo: [NSLocalizedDescriptionKey: "Foreign validation"]
        )

        #expect(AgentError.from(nsError) == .internalError("Foreign validation"))
    }
}
