import Foundation
import Testing

@testable import NexusAI

private final class StubMLXChat: MLXChatGenerating, @unchecked Sendable {
    let cannedChunks: [MLXChunk]
    private(set) var unloaded = false
    private(set) var lastMessages: [MLXChatMessage] = []
    private(set) var lastTools: [MLXToolSpec] = []

    init(cannedChunks: [MLXChunk]) {
        self.cannedChunks = cannedChunks
    }

    func generate(
        messages: [MLXChatMessage],
        tools: [MLXToolSpec],
        params: MLXGenerateParameters
    ) async throws -> AsyncThrowingStream<MLXChunk, Error> {
        lastMessages = messages
        lastTools = tools
        let chunks = cannedChunks
        return AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }

    func unload() async {
        unloaded = true
    }
}

private struct Boom: Error {}

/// A single, re-scriptable generator. `MLXChatEngine.loadIfNeeded` caches the
/// first loaded container, so swapping the loader's return value between calls
/// does NOT change the engine's generator on subsequent `generate`s. The robust
/// way to exercise a different per-call behavior is therefore to install one
/// stub and mutate its script in place, never to swap loader return values.
///
/// Modes per call:
/// - `script` chunks are yielded in order.
/// - If `gated == true`, the stream then parks (continuation retained, never
///   finished) so a consumer can break early and exercise the engine's
///   cancellation/onTermination → `leave()` path. A producer-side
///   `onTermination` finishes the parked continuation when the consumer drops
///   the stream, so nothing leaks between calls.
/// - Else if `failure != nil`, the stream finishes throwing it.
/// - Else the stream finishes normally.
private final class ScriptedStubMLXChat: MLXChatGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var script: [MLXChunk]
    private var failure: Error?
    private var gated: Bool
    private(set) var unloaded = false

    init(script: [MLXChunk], failure: Error? = nil, gated: Bool = false) {
        self.script = script
        self.failure = failure
        self.gated = gated
    }

    func rescript(_ chunks: [MLXChunk], failure: Error? = nil, gated: Bool = false) {
        lock.withLock {
            self.script = chunks
            self.failure = failure
            self.gated = gated
        }
    }

    func generate(
        messages: [MLXChatMessage],
        tools: [MLXToolSpec],
        params: MLXGenerateParameters
    ) async throws -> AsyncThrowingStream<MLXChunk, Error> {
        let (chunks, fail, isGated) = lock.withLock { (script, failure, gated) }
        return AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            if isGated {
                // Park: never finish here. The consumer breaking early drops
                // the stream, firing this onTermination, which finishes the
                // parked continuation so it does not leak.
                continuation.onTermination = { _ in continuation.finish() }
            } else if let fail {
                continuation.finish(throwing: fail)
            } else {
                continuation.finish()
            }
        }
    }

    func unload() async {
        lock.withLock { unloaded = true }
    }
}

/// Thread-safe one-shot gate: the first `consume()` returns `true`, every
/// subsequent call returns `false`. Used to make a loader closure (which is
/// `@Sendable`, so it cannot capture a mutable `var`) throw exactly once.
private final class OneShotGate: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    func consume() -> Bool {
        lock.withLock {
            if fired { return false }
            fired = true
            return true
        }
    }
}

private func collect(
    _ stream: AsyncThrowingStream<MLXChunk, Error>
) async throws -> [MLXChunk] {
    var result: [MLXChunk] = []
    for try await chunk in stream {
        result.append(chunk)
    }
    return result
}

/// Projects `.text` payloads in order so tests can assert exact, distinguishable
/// output without requiring `MLXChunk: Equatable` (the public protocol shape is
/// `Sendable`-only by design).
private func texts(_ chunks: [MLXChunk]) -> [String] {
    chunks.compactMap { chunk in
        if case .text(let value) = chunk { return value }
        return nil
    }
}

@Suite("MLXChatEngine")
struct MLXChatEngineTests {
    @Test("streams and concatenates text chunks")
    func streamsText() async throws {
        let stub = StubMLXChat(cannedChunks: [.text("Hello, "), .text("world"), .text("!")])
        let engine = MLXChatEngine(folder: URL(fileURLWithPath: "/dev/null")) { _, _ in stub }

        let stream = try await engine.generate(
            messages: [MLXChatMessage(role: .user, text: "hi")],
            tools: [],
            params: .default
        )
        let chunks = try await collect(stream)

        let text = chunks.compactMap { chunk -> String? in
            if case .text(let value) = chunk { return value }
            return nil
        }.joined()
        #expect(text == "Hello, world!")
    }

    @Test("forwards tool-call chunks unchanged")
    func forwardsToolCall() async throws {
        let stub = StubMLXChat(cannedChunks: [
            .toolCall(name: "tasks.create", arguments: #"{"title":"Buy milk"}"#)
        ])
        let engine = MLXChatEngine(folder: URL(fileURLWithPath: "/dev/null")) { _, _ in stub }

        let stream = try await engine.generate(
            messages: [MLXChatMessage(role: .user, text: "add a task")],
            tools: [],
            params: .default
        )
        let chunks = try await collect(stream)

        #expect(chunks.count == 1)
        guard case .toolCall(let name, let arguments) = chunks.first else {
            Issue.record("expected a tool-call chunk")
            return
        }
        #expect(name == "tasks.create")
        #expect(arguments == #"{"title":"Buy milk"}"#)
    }

    @Test("unload disposes the loaded container")
    func unloadDisposes() async throws {
        let stub = StubMLXChat(cannedChunks: [.text("warm")])
        let engine = MLXChatEngine(folder: URL(fileURLWithPath: "/dev/null")) { _, _ in stub }

        // Warm up so the engine actually holds a container.
        let stream = try await engine.generate(
            messages: [MLXChatMessage(role: .user, text: "warm")],
            tools: [],
            params: .default
        )
        _ = try await collect(stream)

        #expect(stub.unloaded == false)
        await engine.unload()
        #expect(stub.unloaded == true)
    }

    @Test("forwards messages and tools to the underlying generator")
    func forwardsMessagesAndTools() async throws {
        let stub = StubMLXChat(cannedChunks: [.text("ok")])
        let engine = MLXChatEngine(folder: URL(fileURLWithPath: "/dev/null")) { _, _ in stub }

        let messages = [
            MLXChatMessage(role: .system, text: "be terse"),
            MLXChatMessage(role: .user, text: "hello"),
            MLXChatMessage(role: .tool, text: "{}", toolName: "search", toolCallID: "c1"),
        ]
        let tools = [
            MLXToolSpec(
                name: "search",
                description: "search things",
                parametersJSONSchema: #"{"type":"object"}"#
            )
        ]

        let stream = try await engine.generate(
            messages: messages,
            tools: tools,
            params: .default
        )
        _ = try await collect(stream)

        #expect(stub.lastMessages.count == 3)
        #expect(stub.lastMessages.map(\.role) == [.system, .user, .tool])
        #expect(stub.lastMessages[2].toolName == "search")
        #expect(stub.lastMessages[2].toolCallID == "c1")
        #expect(stub.lastTools.count == 1)
        #expect(stub.lastTools.first?.name == "search")
    }

    @Test("serializes back-to-back generations without deadlock")
    func serializesGenerations() async throws {
        let stub = StubMLXChat(cannedChunks: [.text("a"), .text("b")])
        let engine = MLXChatEngine(folder: URL(fileURLWithPath: "/dev/null")) { _, _ in stub }

        // First generation: fully drain so the busy slot is released.
        let first = try await engine.generate(
            messages: [MLXChatMessage(role: .user, text: "one")],
            tools: [],
            params: .default
        )
        let firstChunks = try await collect(first)
        #expect(firstChunks.count == 2)

        // Second generation must acquire the slot the first released.
        let second = try await engine.generate(
            messages: [MLXChatMessage(role: .user, text: "two")],
            tools: [],
            params: .default
        )
        let secondChunks = try await collect(second)
        #expect(secondChunks.count == 2)
    }

    @Test("queued drained generations both complete")
    func queuedDrainedGenerations() async throws {
        let stub = StubMLXChat(cannedChunks: [.text("x")])
        let engine = MLXChatEngine(folder: URL(fileURLWithPath: "/dev/null")) { _, _ in stub }

        // Two callers each obtain and immediately drain a stream. The engine
        // serializes them via busy/waiters (the second `generate` queues behind
        // the first); both finish because each stream is consumed promptly.
        async let a: [MLXChunk] = collect(
            try await engine.generate(
                messages: [MLXChatMessage(role: .user, text: "a")],
                tools: [],
                params: .default
            )
        )
        async let b: [MLXChunk] = collect(
            try await engine.generate(
                messages: [MLXChatMessage(role: .user, text: "b")],
                tools: [],
                params: .default
            )
        )
        let (resultA, resultB) = try await (a, b)
        #expect(resultA.count == 1)
        #expect(resultB.count == 1)
    }

    // `.timeLimit` turns a slot-leak regression (which deadlocks the second
    // `generate` in the engine's unbounded `enter()` `withCheckedContinuation`)
    // into a clean, attributable failing test instead of a job-level hang.
    // `.minutes(1)` is Swift Testing's minimum granularity; these run in ~1ms.
    @Test(
        "loader-closure throw releases the slot and rethrows synchronously",
        .timeLimit(.minutes(1))
    )
    func loaderThrowReleasesSlot() async throws {
        struct LoaderBoom: Error {}

        let goodStub = StubMLXChat(cannedChunks: [.text("ok")])
        // The loader throws on its first invocation only. Because that load
        // fails, the engine caches nothing, so the second `generate` re-invokes
        // the loader (now succeeding) — the loader-return-value here genuinely
        // changes per call, unlike the cached-success case.
        let throwOnce = OneShotGate()
        let loader: MLXChatEngine.Loader = { _, _ in
            if throwOnce.consume() {
                throw LoaderBoom()
            }
            return goodStub
        }
        let engine = MLXChatEngine(folder: URL(fileURLWithPath: "/dev/null"), loader: loader)

        // First `generate`: the loader closure throws. `enter()` ran, so the slot
        // must be released on the synchronous error path or the engine deadlocks.
        await #expect(throws: LoaderBoom.self) {
            _ = try await engine.generate(
                messages: [MLXChatMessage(role: .user, text: "one")],
                tools: [],
                params: .default
            )
        }

        // A subsequent `generate` with a working loader must still acquire the
        // slot — proof the failing path called `leave()`.
        let stream = try await engine.generate(
            messages: [MLXChatMessage(role: .user, text: "two")],
            tools: [],
            params: .default
        )
        let chunks = try await collect(stream)
        #expect(texts(chunks) == ["ok"])
    }

    @Test(
        "early consumer break releases the slot via onTermination",
        .timeLimit(.minutes(1))
    )
    func earlyBreakReleasesSlot() async throws {
        // One stub, installed once and cached by the engine. First call: gated
        // (yields "first" then parks). After the early break we rescript the
        // SAME stub to emit a distinguishable terminal chunk. This sidesteps
        // the engine's container caching entirely (swapping a loader's return
        // value would be ignored on the cached second call).
        let stub = ScriptedStubMLXChat(script: [.text("first")], gated: true)
        let engine = MLXChatEngine(folder: URL(fileURLWithPath: "/dev/null")) { _, _ in stub }

        // Obtain a stream, consume exactly one chunk, then break early. The
        // gated stream never finishes on its own, so the only way the slot is
        // released is the released-stream → `onTermination` → `task.cancel()`
        // → `leave()` path. `next()` on an `AsyncThrowingStream` iterator is
        // cancellation-aware, so the wrapper task's `for try await` exits
        // cleanly when cancelled. The stream is scoped inside a child `Task`:
        // an async `let` does not reliably deinit at a `do {}` boundary
        // (coroutine machinery extends its lifetime), but `Task` teardown
        // deterministically releases the body's locals before `.value` returns.
        try await Task {
            var stream: AsyncThrowingStream<MLXChunk, Error>? = try await engine.generate(
                messages: [MLXChatMessage(role: .user, text: "one")],
                tools: [],
                params: .default
            )
            for try await chunk in stream! {
                guard case .text(let value) = chunk else {
                    Issue.record("expected a text chunk")
                    return
                }
                #expect(value == "first")
                break
            }
            stream = nil  // release the only outer reference deterministically
            _ = stream
        }.value
        // onTermination has now fired → wrapper task cancelled → leave() ran.

        // A fresh `generate` on the SAME cached stub must complete and produce
        // the rescripted, distinguishable output — proof the slot was freed
        // (it would otherwise park in `enter()` forever) and that we are
        // exercising the cached generator, not a stale loader swap.
        stub.rescript([.text("RECOVERED")])
        let next = try await engine.generate(
            messages: [MLXChatMessage(role: .user, text: "two")],
            tools: [],
            params: .default
        )
        let chunks = try await collect(next)
        #expect(texts(chunks) == ["RECOVERED"])
    }

    @Test(
        "mid-stream error propagates then the slot is released",
        .timeLimit(.minutes(1))
    )
    func midStreamErrorReleasesSlot() async throws {
        // One stub, installed once and cached. First call yields "a", "b" then
        // finishes throwing — the consumer must receive both chunks and then
        // the propagated error.
        let stub = ScriptedStubMLXChat(script: [.text("a"), .text("b")], failure: Boom())
        let engine = MLXChatEngine(folder: URL(fileURLWithPath: "/dev/null")) { _, _ in stub }

        let stream = try await engine.generate(
            messages: [MLXChatMessage(role: .user, text: "one")],
            tools: [],
            params: .default
        )
        var received: [String] = []
        var thrown: Error?
        do {
            for try await chunk in stream {
                if case .text(let value) = chunk { received.append(value) }
            }
        } catch {
            thrown = error
        }
        #expect(received == ["a", "b"])
        #expect(thrown is Boom)

        // The error path must still `leave()`. Rescript the SAME cached stub to
        // succeed with distinguishable output; a fresh `generate` that produces
        // it proves the slot was freed (else this would park in `enter()`).
        stub.rescript([.text("RECOVERED")])
        let next = try await engine.generate(
            messages: [MLXChatMessage(role: .user, text: "two")],
            tools: [],
            params: .default
        )
        let chunks = try await collect(next)
        #expect(texts(chunks) == ["RECOVERED"])
    }
}
