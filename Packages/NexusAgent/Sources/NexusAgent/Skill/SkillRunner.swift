import Foundation
import NexusAI

public enum SkillRunError: Error, Equatable {
    case invalidOutputAfterRetry(reason: String)
    case inferenceFailed(String)
}

public struct SkillRunResult<Output: Sendable & Equatable>: Sendable, Equatable {
    public let output: Output
    public let rawText: String
    public let assembledContext: AssembledContext
}

@MainActor
public final class SkillRunner {
    private let inference: any SkillInference
    private let assembler: ContextAssembler

    public init(inference: any SkillInference, assembler: ContextAssembler) {
        self.inference = inference
        self.assembler = assembler
    }

    /// Steps 1–4: assemble context → one inference → parse/validate → one repair retry → clean failure.
    /// Step 5 (Output → Proposal) is the skill-specific layer, not here.
    public func run<Output>(
        _ skill: AssistantSkill<Output>,
        focus: ContextFocus,
        userText: String,
        now: Date = .now
    ) async throws -> SkillRunResult<Output> {
        let assembled = await assembler.assemble(skill.contextRecipe, focus: focus, now: now)
        let basePrompt = """
            \(userText)

            Respond ONLY with output matching this contract: \(skill.output.schemaDescription)
            """
        let firstRequest = makeRequest(skill: skill, prompt: basePrompt, context: assembled.renderedBlocks())
        let firstText: String
        do {
            firstText = try await inference.generate(firstRequest).text
        } catch {
            throw SkillRunError.inferenceFailed("\(error)")
        }

        do {
            let output = try skill.output.decode(firstText)
            return SkillRunResult(output: output, rawText: firstText, assembledContext: assembled)
        } catch let OutputContractError.invalid(reason) {
            // one repair retry
            let repairPrompt = """
                \(basePrompt)

                Your previous output was invalid because: \(reason)
                Previous output was:
                \(firstText)
                Produce a corrected output that matches the contract exactly.
                """
            let retryRequest = makeRequest(skill: skill, prompt: repairPrompt, context: assembled.renderedBlocks())
            let retryText: String
            do {
                retryText = try await inference.generate(retryRequest).text
            } catch {
                throw SkillRunError.inferenceFailed("\(error)")
            }
            do {
                let output = try skill.output.decode(retryText)
                return SkillRunResult(output: output, rawText: retryText, assembledContext: assembled)
            } catch let OutputContractError.invalid(reason2) {
                throw SkillRunError.invalidOutputAfterRetry(reason: reason2)
            }
        }
    }

    private func makeRequest<Output>(
        skill: AssistantSkill<Output>,
        prompt: String,
        context: [String]
    ) -> AIRequest {
        AIRequest(
            prompt: prompt,
            capability: .generate,
            connectivity: .offlineOnly,
            cost: .free,
            providerPreference: .auto,
            context: context,
            tools: skill.allowsToolCalling && !skill.toolNames.isEmpty ? [] : nil,
            systemPrompt: skill.systemPrompt)
    }
}
