import Foundation
import NexusCore
import Testing

@testable import NexusAI

// MARK: - MLXChatConverters tests

@Suite("MLXChatConverters")
struct MLXChatConvertersTests {

    // MARK: AIToolSpec → MLXToolSpec

    @Test("AIToolSpec→MLXToolSpec copies all fields")
    func toolSpecFieldFidelity() {
        let spec = AIToolSpec(
            name: "tasks.create",
            description: "Creates a task",
            parametersJSONSchema: #"{"type":"object","properties":{"title":{"type":"string"}}}"#
        )
        let result = MLXChatConverters.mlxToolSpec(from: spec)
        #expect(result.name == spec.name)
        #expect(result.description == spec.description)
        #expect(result.parametersJSONSchema == spec.parametersJSONSchema)
    }

    @Test("Array of AIToolSpec→[MLXToolSpec] preserves order and field fidelity")
    func toolSpecArrayForm() {
        let specs = [
            AIToolSpec(name: "alpha", description: "A", parametersJSONSchema: "{}"),
            AIToolSpec(name: "beta", description: "B", parametersJSONSchema: #"{"x":1}"#),
        ]
        let results = MLXChatConverters.mlxToolSpecs(from: specs)
        #expect(results.count == 2)
        #expect(results[0].name == "alpha")
        #expect(results[1].name == "beta")
        #expect(results[1].parametersJSONSchema == #"{"x":1}"#)
    }

    // MARK: AIChatMessage → MLXChatMessage

    @Test("system role maps to .system")
    func roleSystem() {
        let msg = AIChatMessage(role: .system, text: "You are Nexus.")
        let result = MLXChatConverters.mlxChatMessage(from: msg)
        #expect(result.role == .system)
        #expect(result.text == "You are Nexus.")
        #expect(result.toolName == nil)
        #expect(result.toolCallID == nil)
    }

    @Test("user role maps to .user")
    func roleUser() {
        let msg = AIChatMessage(role: .user, text: "What's on my plate today?")
        let result = MLXChatConverters.mlxChatMessage(from: msg)
        #expect(result.role == .user)
        #expect(result.text == "What's on my plate today?")
    }

    @Test("assistant role maps to .assistant")
    func roleAssistant() {
        let msg = AIChatMessage(role: .assistant, text: "Here are your tasks.")
        let result = MLXChatConverters.mlxChatMessage(from: msg)
        #expect(result.role == .assistant)
        #expect(result.text == "Here are your tasks.")
    }

    @Test("tool role maps to .tool with toolName and toolCallID carried through")
    func roleTool() {
        let msg = AIChatMessage(
            role: .tool,
            text: #"{"count":3}"#,
            toolName: "tasks.list",
            toolCallID: "call-42"
        )
        let result = MLXChatConverters.mlxChatMessage(from: msg)
        #expect(result.role == .tool)
        #expect(result.text == #"{"count":3}"#)
        #expect(result.toolName == "tasks.list")
        #expect(result.toolCallID == "call-42")
    }

    @Test("toolName and toolCallID nil passthrough for non-tool roles")
    func nilToolFieldsPassthrough() {
        let msg = AIChatMessage(role: .user, text: "Hello", toolName: nil, toolCallID: nil)
        let result = MLXChatConverters.mlxChatMessage(from: msg)
        #expect(result.toolName == nil)
        #expect(result.toolCallID == nil)
    }

    @Test("Array of AIChatMessage→[MLXChatMessage] preserves order and all roles")
    func chatMessageArrayForm() {
        let messages: [AIChatMessage] = [
            AIChatMessage(role: .system, text: "sys"),
            AIChatMessage(role: .user, text: "usr"),
            AIChatMessage(role: .assistant, text: "asst"),
            AIChatMessage(role: .tool, text: "result", toolName: "t", toolCallID: "c"),
        ]
        let results = MLXChatConverters.mlxChatMessages(from: messages)
        #expect(results.count == 4)
        #expect(results[0].role == .system)
        #expect(results[1].role == .user)
        #expect(results[2].role == .assistant)
        #expect(results[3].role == .tool)
        #expect(results[3].toolName == "t")
        #expect(results[3].toolCallID == "c")
    }

    // MARK: MLXChunk.toolCall → AIToolCall

    @Test("well-formed JSON object args decode to correct JSONValue tree")
    func toolCallWellFormedArgs() {
        let call = MLXChatConverters.aiToolCall(
            name: "tasks.create",
            arguments: #"{"title":"Buy milk","priority":"p1"}"#
        )
        #expect(call.name == "tasks.create")
        if case .object(let dict) = call.arguments {
            #expect(dict["title"] == .string("Buy milk"))
            #expect(dict["priority"] == .string("p1"))
        } else {
            Issue.record("Expected .object, got \(call.arguments)")
        }
    }

    @Test("well-formed nested JSON args decode fully")
    func toolCallNestedArgs() {
        let call = MLXChatConverters.aiToolCall(
            name: "agent.remember",
            arguments: #"{"key":"name","value":{"first":"Kacper","last":"Pietrzyk"}}"#
        )
        #expect(call.name == "agent.remember")
        guard case .object(let dict) = call.arguments,
            case .object(let inner) = dict["value"]
        else {
            Issue.record("Expected nested object, got \(call.arguments)")
            return
        }
        #expect(inner["first"] == .string("Kacper"))
    }

    @Test("malformed JSON args produce empty-object with name preserved, never throws")
    func toolCallMalformedJSON() {
        let call = MLXChatConverters.aiToolCall(
            name: "tasks.delete",
            arguments: "{not json"
        )
        #expect(call.name == "tasks.delete")
        #expect(call.arguments == .object([:]))
    }

    @Test("valid-JSON but non-object args (array) produce empty-object, name preserved")
    func toolCallValidJSONNotObject_array() {
        let call = MLXChatConverters.aiToolCall(
            name: "tasks.list",
            arguments: "[1,2,3]"
        )
        #expect(call.name == "tasks.list")
        #expect(call.arguments == .object([:]))
    }

    @Test("valid-JSON but non-object args (string) produce empty-object, name preserved")
    func toolCallValidJSONNotObject_string() {
        let call = MLXChatConverters.aiToolCall(
            name: "tasks.get",
            arguments: #""just a string""#
        )
        #expect(call.name == "tasks.get")
        #expect(call.arguments == .object([:]))
    }

    @Test("empty JSON object args produce empty-object value")
    func toolCallEmptyObjectArgs() {
        let call = MLXChatConverters.aiToolCall(
            name: "agent.noop",
            arguments: "{}"
        )
        #expect(call.name == "agent.noop")
        #expect(call.arguments == .object([:]))
    }

    @Test("empty string args (not valid JSON) produce empty-object, name preserved")
    func toolCallEmptyStringArgs() {
        let call = MLXChatConverters.aiToolCall(
            name: "tasks.daily_summary",
            arguments: ""
        )
        #expect(call.name == "tasks.daily_summary")
        #expect(call.arguments == .object([:]))
    }
}
