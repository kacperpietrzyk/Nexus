import Foundation
import MLXLLM
import MLXLMCommon

// MARK: - Public protocol surface

/// A single chat message handed to the on-device MLX engine.
///
/// The system prompt is a first-class message with `role == .system`. There is no
/// separate `systemPrompt` parameter — mlx-swift-lm renders the model's own chat
/// template from the structured message list.
public struct MLXChatMessage: Sendable {
    public enum Role: Sendable { case system, user, assistant, tool }

    public let role: Role
    public let text: String
    /// Set for the `.tool` role: which tool produced this result.
    public let toolName: String?
    /// Optional correlation id; `nil` for now.
    public let toolCallID: String?

    public init(role: Role, text: String, toolName: String? = nil, toolCallID: String? = nil) {
        self.role = role
        self.text = text
        self.toolName = toolName
        self.toolCallID = toolCallID
    }
}

/// Declarative description of a tool the model may call.
public struct MLXToolSpec: Sendable {
    public let name: String
    public let description: String
    /// JSON Schema for the tool's parameters, encoded as a JSON string.
    public let parametersJSONSchema: String

    public init(name: String, description: String, parametersJSONSchema: String) {
        self.name = name
        self.description = description
        self.parametersJSONSchema = parametersJSONSchema
    }
}

/// One streamed unit of model output. Deliberately leaks no mlx-swift-lm /
/// swift-transformers type so it stays constructible by callers and stub tests.
public enum MLXChunk: Sendable {
    case text(String)
    /// `arguments` is a compact JSON object string (Sendable-safe; no upstream types).
    case toolCall(name: String, arguments: String)
    case info(promptTokens: Int, completionTokens: Int)
}

/// Sampling / length controls. There is no grammar / constrained-sampling option:
/// mlx-swift-lm 3.31.3 ships none.
public struct MLXGenerateParameters: Sendable {
    public var temperature: Double
    public var maxTokens: Int
    public var topP: Double?

    public init(temperature: Double = 0.7, maxTokens: Int = 4096, topP: Double? = nil) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
    }

    // Low temperature: the on-device 12B (qat 4-bit) needs tight sampling to hold a
    // structured format (real tool call / direct answer) instead of wandering into a
    // fabricated ReAct transcript. 0.7 was far too hot for this grounded, structured task.
    public static let `default` = MLXGenerateParameters(temperature: 0.15)
}

/// Abstraction over an on-device chat generator. The unit tests substitute a stub;
/// production uses `LiveMLXChatContainer`.
public protocol MLXChatGenerating: Sendable {
    func generate(
        messages: [MLXChatMessage],
        tools: [MLXToolSpec],
        params: MLXGenerateParameters
    ) async throws -> AsyncThrowingStream<MLXChunk, Error>

    func unload() async
}

// MARK: - Errors

public enum MLXChatEngineError: Error, Sendable {
    /// A tool spec's `parametersJSONSchema` was not a JSON object.
    case invalidToolParametersSchema(toolName: String)
    /// The app is not foreground-active, so GPU work is refused (issue #51).
    /// A *catchable* Swift error raised BEFORE any Metal command buffer is
    /// submitted — the alternative is MLX's uncatchable C++ `throw` →
    /// `std::terminate` when the OS rejects a background submission.
    case backgrounded
}

// MARK: - Engine actor

/// Serializes load + generation against a single loaded model, mirroring the
/// `WhisperKitProviderEngine` busy/waiters pattern. Concurrency is capped at one
/// in-flight generation per engine.
public actor MLXChatEngine {
    public typealias Loader =
        @Sendable (URL, MLXGenerateParameters) async throws ->
        any MLXChatGenerating

    /// Resolved lazily at every cold load so a model assignment that changed
    /// after `init` (Welcome download / Settings re-assign) targets the
    /// currently-assigned folder, not the one captured at composition time.
    private let folderProvider: @Sendable () -> URL
    private let loader: Loader
    /// Strong optional — not `weak` because `MLXLifecycleController` never holds
    /// a reference back to the engine (it is state-only), so there is no retain
    /// cycle. A `weak` ref would silently drop notifications whenever the
    /// composition graph has any ownership gap, defeating the feature entirely.
    private let lifecycle: MLXLifecycleController?
    private var container: (any MLXChatGenerating)?
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// Monotonic load-epoch. Bumped by `unload()` so a load that was in flight
    /// when `unload()` ran can detect on resume that it was superseded and not
    /// resurrect a model `unload()` was supposed to drop. Mirrors
    /// `MLXEmbedderEngine.loadGeneration` exactly — the chat engine's
    /// rebind path (unload → preload on assignment change) activates the same
    /// unload-during-load race the embedder already solved.
    private var loadGeneration = 0

    /// Static-folder init. Preserved verbatim as the test surface — every
    /// existing engine test constructs the engine with a fixed `folder:` and
    /// must keep compiling unchanged. Internally it just wraps the URL as a
    /// constant provider.
    public init(
        folder: URL,
        lifecycle: MLXLifecycleController? = nil,
        loader: @escaping Loader = { folder, params in
            try await LiveMLXChatContainer.load(folder: folder, params: params)
        }
    ) {
        self.init(folderProvider: { folder }, lifecycle: lifecycle, loader: loader)
    }

    /// Dynamic-folder init used by `AIComposition.makeGraph`: the folder is
    /// re-resolved at every cold load via `lifecycle.chatFolderURL()`, so a
    /// post-launch assignment change rebinds the next load to the new model.
    public init(
        folderProvider: @escaping @Sendable () -> URL,
        lifecycle: MLXLifecycleController? = nil,
        loader: @escaping Loader = { folder, params in
            try await LiveMLXChatContainer.load(folder: folder, params: params)
        }
    ) {
        self.folderProvider = folderProvider
        self.lifecycle = lifecycle
        self.loader = loader
    }

    public func generate(
        messages: [MLXChatMessage],
        tools: [MLXToolSpec],
        params: MLXGenerateParameters
    ) async throws -> AsyncThrowingStream<MLXChunk, Error> {
        // Issue #51: refuse to dispatch GPU work in the background BEFORE taking
        // the busy token or loading weights — loading quantized weights itself
        // triggers `MLX.eval`, which submits the command buffer the OS rejects.
        // `nil` lifecycle (stub tests / non-graph construction) = no gate.
        if let lifecycle, !lifecycle.isForegroundActive {
            throw MLXChatEngineError.backgrounded
        }
        await enter()
        // Refresh the idle clock now that the caller holds the busy token and is
        // genuinely about to use the engine. Fired after enter() so a caller that is
        // cancelled while queued does not ghost-touch the idle clock for a session
        // that never runs. No-op when the slot is empty (Task-15 guard on touchChat).
        lifecycle?.touchChat()

        let inner: AsyncThrowingStream<MLXChunk, Error>
        do {
            let generator = try await loadIfNeeded(params: params)
            inner = try await generator.generate(
                messages: messages,
                tools: tools,
                params: params
            )
        } catch {
            // Synchronous failure before the wrapper stream exists: release the slot.
            leave()
            throw error
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await chunk in inner {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                await self.leave()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Warms the chat container without routing a synthetic generate request.
    /// Held under the SAME busy gate `generate()` uses so a concurrent
    /// generation cannot race the cold load, and the slot is released on every
    /// path (success OR throw) — a leaked busy token would deadlock the next
    /// `generate`/`preload` in `enter()` forever.
    public func preload() async throws {
        // Issue #51: the background-launch crash repro — a detached preload that
        // loads weights (→ `MLX.eval`) while the scene is not yet `.active`.
        // Gate before `enter()` so the busy token is never taken when refused.
        if let lifecycle, !lifecycle.isForegroundActive {
            throw MLXChatEngineError.backgrounded
        }
        await enter()
        do {
            _ = try await loadIfNeeded(params: .default)
        } catch {
            leave()
            throw error
        }
        leave()
    }

    public func unload() async {
        await container?.unload()
        container = nil
        // Bump the epoch so a load that is currently suspended in
        // `loadIfNeeded` detects on resume that it was superseded and does not
        // resurrect cached state / phantom-promote the lifecycle slot.
        loadGeneration += 1
        // Keep the lifecycle slot consistent with engine teardown: a dropped
        // container must not read `.loaded`. Without this, `reload()`'s
        // unload→preload window would leave the slot `.loaded` against a nil
        // container, letting a concurrent `route` slip through onto a stale
        // (just-dropped) model. No production caller invokes `engine.unload()`
        // outside this engine's own `reload()` path, so this only tightens
        // state — it never regresses an existing caller.
        lifecycle?.unloadChat()
    }

    // Only reached from `generate`/`preload`, which hold the busy gate via
    // `enter()`, so concurrent cold loads cannot both reach the cache-commit
    // line; the cold-load markChatLoaded() therefore fires at most once per
    // logical load. The cached-hit fast path additionally re-marks the slot so a
    // swept-but-still-resident container is re-promoted to available.
    //
    // The post-await write is epoch-guarded against a concurrent `unload()`
    // (mirrors `MLXEmbedderEngine.loadIfNeeded`): `loader` suspends, and if
    // `unload()` runs in that window it bumps `loadGeneration`. On resume the
    // captured epoch is stale ⇒ the caller still receives its generator (do NOT
    // fail it), but the engine does NOT cache it or mark the slot loaded — it
    // unloads the now-orphaned container so a successful `unload()` still means
    // the model is freed. The chat engine has no in-flight `Task` registry
    // (load is single-flight via the `enter()` busy gate, not a cached task),
    // so there is no symmetric catch-side bookkeeping to undo.
    private func loadIfNeeded(
        params: MLXGenerateParameters
    ) async throws -> any MLXChatGenerating {
        if let container {
            // Fast path re-`markChatLoaded()`: after an idle sweep (or thermal /
            // memory-guard eviction) the lifecycle slot is `.empty` while
            // `container` stays non-nil. Re-marking re-promotes the still-resident
            // container so `isChatAvailable` flips back true on the next ungated
            // hit (e.g. `preload()` on foreground return), instead of leaving MLX
            // silently unavailable until model-reassign or app restart.
            //
            // Safe in every state: in the already-`.loaded` case this only resets
            // `idleSince` (same as the `touchChat()` `generate` already performs),
            // and it cannot create phantom thermal availability because
            // `isChatAvailable` stays gated by the separate `thermalDegraded`
            // flag.
            lifecycle?.markChatLoaded()
            return container
        }
        let generation = loadGeneration
        let loaded = try await loader(folderProvider(), params)
        if loadGeneration == generation {
            container = loaded
            // Notify the lifecycle controller that the chat slot is now live.
            // Called on the winning (non-stale) cold-load path after the cache is
            // committed; the cached-hit fast path above also re-marks so a
            // swept-then-re-hit slot is re-promoted, and the stale `else` branch
            // unloads the orphan without caching so it cannot create phantom
            // availability.
            lifecycle?.markChatLoaded()
        } else {
            // A superseding `unload()` ran mid-load: honor it.
            await loaded.unload()
        }
        return loaded
    }

    private func enter() async {
        if !busy {
            busy = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func leave() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

// MARK: - Live container (real mlx-swift-lm 3.31.3 bridge)

/// Real `MLXChatGenerating` backed by mlx-swift-lm's `ModelContainer`.
///
/// `MLXLLM` must be linked: `loadModelContainer(from:using:)` discovers its factory
/// dynamically via `NSClassFromString("MLXLLM.TrampolineModelFactory")`. We never use
/// `ChatSession` — its built-in tool-call restart loop would bypass the higher-level
/// `ToolDispatcher` (audit/undo). We drive `prepare` + `generate` directly.
public struct LiveMLXChatContainer: MLXChatGenerating {
    private let container: ModelContainer

    public static func load(
        folder: URL,
        params: MLXGenerateParameters
    ) async throws -> any MLXChatGenerating {
        // `params` does not influence loading; sampling is applied per-generate.
        _ = params
        let container = try await loadModelContainer(
            from: folder,
            using: SwiftTransformersTokenizerLoader()
        )
        return LiveMLXChatContainer(container: container)
    }

    public func generate(
        messages: [MLXChatMessage],
        tools: [MLXToolSpec],
        params: MLXGenerateParameters
    ) async throws -> AsyncThrowingStream<MLXChunk, Error> {
        let chat = messages.map(Self.makeChatMessage)
        let toolSpecs = try Self.makeToolSpecs(tools)
        let userInput = UserInput(
            chat: chat,
            tools: toolSpecs.isEmpty ? nil : toolSpecs
        )
        let parameters = Self.makeGenerateParameters(params)

        // `prepare` and `generate` throw synchronously during prefill; surface that
        // via `finish(throwing:)` since the inner upstream stream is non-throwing.
        let lmInput = try await container.prepare(input: userInput)
        let upstream = try await container.generate(
            input: lmInput,
            parameters: parameters
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                for await generation in upstream {
                    switch generation {
                    case .chunk(let text):
                        continuation.yield(.text(text))
                    case .toolCall(let call):
                        do {
                            let json = try Self.encodeArguments(call.function.arguments)
                            continuation.yield(
                                .toolCall(name: call.function.name, arguments: json)
                            )
                        } catch {
                            continuation.finish(throwing: error)
                            return
                        }
                    case .info(let info):
                        continuation.yield(
                            .info(
                                promptTokens: info.promptTokenCount,
                                completionTokens: info.generationTokenCount
                            )
                        )
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func unload() async {
        // mlx-swift-lm exposes no explicit teardown; dropping the only strong
        // reference lets ARC release the container and its weights. The engine
        // nils its `container` field after this returns.
    }

    // MARK: Mapping helpers

    private static func makeChatMessage(_ message: MLXChatMessage) -> Chat.Message {
        let role: Chat.Message.Role
        switch message.role {
        case .system: role = .system
        case .user: role = .user
        case .assistant: role = .assistant
        case .tool: role = .tool
        }
        // `Chat.Message`/`DefaultMessageGenerator` carry only role + content, so a
        // `.tool` message's `toolName`/`toolCallID` are not surfaced to the template
        // at Task 10 scope. The protocol still preserves them for the Task 11/12
        // dispatcher, which owns richer tool-result prompt construction.
        return Chat.Message(role: role, content: message.text)
    }

    private static func makeToolSpecs(_ tools: [MLXToolSpec]) throws -> [ToolSpec] {
        try tools.map { tool in
            let parameters = try parseJSONObject(
                tool.parametersJSONSchema,
                toolName: tool.name
            )
            return [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": parameters,
                ] as [String: any Sendable],
            ] as ToolSpec
        }
    }

    private static func makeGenerateParameters(
        _ params: MLXGenerateParameters
    ) -> GenerateParameters {
        var parameters = GenerateParameters(
            maxTokens: params.maxTokens,
            temperature: Float(params.temperature)
        )
        if let topP = params.topP {
            parameters.topP = Float(topP)
        }
        return parameters
    }

    private static func encodeArguments(_ arguments: [String: MLXLMCommon.JSONValue]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(arguments)
        // `JSONEncoder` always emits valid UTF-8; the empty fallback is unreachable.
        return String(bytes: data, encoding: .utf8) ?? "{}"
    }

    private static func parseJSONObject(
        _ json: String,
        toolName: String
    ) throws -> [String: any Sendable] {
        guard let data = json.data(using: .utf8),
            case .object(let object) = try? JSONDecoder().decode(MLXLMCommon.JSONValue.self, from: data)
        else {
            throw MLXChatEngineError.invalidToolParametersSchema(toolName: toolName)
        }
        return object.mapValues(Self.sendableValue)
    }

    /// Recursively converts a `MLXLMCommon.JSONValue` into `any Sendable`. We cannot use
    /// `JSONSerialization` here: it yields `NSDictionary`/`NSNumber`, which are not
    /// `Sendable` and would be rejected in a `[String: any Sendable]` slot.
    private static func sendableValue(_ value: MLXLMCommon.JSONValue) -> any Sendable {
        switch value {
        case .null:
            return NSNull()
        case .bool(let bool):
            return bool
        case .int(let int):
            return int
        case .double(let double):
            return double
        case .string(let string):
            return string
        case .array(let array):
            return array.map(Self.sendableValue) as [any Sendable]
        case .object(let object):
            return object.mapValues(Self.sendableValue) as [String: any Sendable]
        }
    }
}
