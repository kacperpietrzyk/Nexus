import Foundation
import NexusAI
import NexusCore
import Testing
import os

@testable import TasksFeature

@Suite("CapturePaneState")
struct CapturePaneStateTests {
    let now = Date(timeIntervalSince1970: 1_777_000_000)

    @Test("empty input yields empty result")
    func emptyInputEmptyResult() async {
        let state = await CapturePaneState(
            parser: HandcodedParser(),
            locale: Locale(identifier: "en"),
            nowProvider: { [now] in now },
            debounce: .zero
        )
        await state.handleInputChange("")
        let result = await state.lastResult
        #expect(result == nil)
    }

    @Test("non-empty input populates lastResult after parse")
    func parsePopulatesResult() async {
        let state = await CapturePaneState(
            parser: HandcodedParser(),
            locale: Locale(identifier: "en"),
            nowProvider: { [now] in now },
            debounce: .zero
        )
        await state.handleInputChange("buy bread tomorrow !2")
        let result = await state.lastResult
        #expect(result?.title == "buy bread")
        #expect(result?.priority == .medium)
        #expect(result?.dueAt != nil)
    }

    @Test("repository.insert called with parsed values on commit")
    @MainActor
    func commitInsertsTask() async throws {
        let recorder = RecordingRepository()
        let endAt = Date(timeIntervalSince1970: 1_778_162_400)
        let deadlineAt = Date(timeIntervalSince1970: 1_778_508_000)
        let state = CapturePaneState(
            parser: FixedParser(
                result: ParseResult(
                    title: "call mom",
                    endAt: endAt,
                    deadlineAt: deadlineAt,
                    priority: .high,
                    tags: ["personal"],
                    confidence: 1.0
                )),
            locale: Locale(identifier: "en"),
            nowProvider: { [now] in now },
            debounce: .zero
        )
        await state.handleInputChange("call mom !1 #personal")
        await state.commit { item in
            recorder.insertedTitle = item.title
            recorder.insertedPriority = item.priority
            recorder.insertedTags = item.tags
            recorder.insertedEndAt = item.endAt
            recorder.insertedDeadlineAt = item.deadlineAt
        }
        #expect(recorder.insertedTitle == "call mom")
        #expect(recorder.insertedPriority == .high)
        #expect(recorder.insertedTags == ["personal"])
        #expect(recorder.insertedEndAt == endAt)
        #expect(recorder.insertedDeadlineAt == deadlineAt)
        let resetInput = state.input
        #expect(resetInput.isEmpty, "commit must reset the input string")
    }

    @Test("handleInputChange skips redundant write when value unchanged")
    @MainActor
    func dedupRedundantWrite() async {
        let state = CapturePaneState(
            parser: HandcodedParser(),
            locale: Locale(identifier: "en"),
            nowProvider: { [now] in now },
            debounce: .zero
        )
        state.input = "buy bread"
        // withObservationTracking's onChange is @Sendable per its type signature,
        // independent of caller actor isolation — a plain `var` cannot be captured.
        let counter = OSAllocatedUnfairLock(initialState: 0)
        withObservationTracking {
            _ = state.input
        } onChange: {
            counter.withLock { $0 += 1 }
        }
        await state.handleInputChange("buy bread")
        #expect(counter.withLock { $0 } == 0, "redundant input write must not fire observation")
    }

    @MainActor
    final class RecordingRepository {
        var insertedTitle: String?
        var insertedPriority: TaskPriority?
        var insertedTags: [String] = []
        var insertedEndAt: Date?
        var insertedDeadlineAt: Date?
    }

    private struct FixedParser: NLParser {
        let result: ParseResult

        func parse(_: String, locale _: Locale, now _: Date, calendar _: Calendar) async -> ParseResult {
            result
        }
    }
}
