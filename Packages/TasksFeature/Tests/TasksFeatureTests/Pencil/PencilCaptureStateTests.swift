#if os(iOS)
import TasksFeature
import Testing

@MainActor
@Suite("PencilCaptureState")
struct PencilCaptureStateTests {

    @Test("recognized text is editable before commit")
    func recognizedTextIsEditable() async throws {
        let state = PencilCaptureState(recognize: { "call Asia tomorrow" })

        await state.recognizeDrawing()
        state.text = "call Asia tomorrow 9"

        #expect(state.text == "call Asia tomorrow 9")
    }
}
#endif
