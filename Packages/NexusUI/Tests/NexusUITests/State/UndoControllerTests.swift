import Testing

@testable import NexusUI

@MainActor
@Suite struct UndoControllerTests {
    @Test func showPresentsToast() {
        let controller = UndoController()
        controller.show(message: "Deleted 3") {}
        #expect(controller.isPresenting)
        #expect(controller.current?.message == "Deleted 3")
    }

    @Test func performUndoRunsClosureAndClears() {
        let controller = UndoController()
        var undone = 0
        controller.show(message: "Deleted 1") { undone += 1 }
        controller.performUndo()
        #expect(undone == 1)
        #expect(controller.isPresenting == false)
    }

    @Test func dismissClearsWithoutRunningUndo() {
        let controller = UndoController()
        var undone = 0
        controller.show(message: "Deleted 1") { undone += 1 }
        controller.dismiss()
        #expect(undone == 0)
        #expect(controller.isPresenting == false)
    }

    @Test func performUndoIsNoOpWhenNothingShowing() {
        let controller = UndoController()
        controller.performUndo()  // must not crash
        #expect(controller.isPresenting == false)
    }

    @Test func showReplacesPreviousToast() {
        let controller = UndoController()
        controller.show(message: "first") {}
        let firstID = controller.current?.id
        controller.show(message: "second") {}
        #expect(controller.current?.message == "second")
        #expect(controller.current?.id != firstID)
    }

    @Test func autoDismissFiresAfterDuration() async throws {
        let controller = UndoController(duration: 0.05)
        controller.show(message: "Deleted 1") {}
        #expect(controller.isPresenting)
        try await Task.sleep(for: .seconds(0.15))
        #expect(controller.isPresenting == false)
    }
}
