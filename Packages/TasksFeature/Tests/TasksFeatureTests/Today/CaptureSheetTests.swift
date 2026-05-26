import Testing

@testable import TasksFeature

@Suite("CaptureSheet v4")
struct CaptureSheetTests {
    @Test("Builds with default and voice modes")
    @MainActor
    func builds() {
        _ = CaptureSheet()
        _ = CaptureSheet(initialMode: .voiceMemo)
    }

    @Test("Touch chrome hides desktop shortcuts and top confirmation")
    func touchChrome() {
        #expect(CaptureSheetChrome.keyboardHint("T", idiom: .touch) == nil)
        #expect(CaptureSheetChrome.keyboardHint("V", idiom: .touch) == nil)
        #expect(!CaptureSheetChrome.showsTopConfirmationAction(idiom: .touch))
        #expect(CaptureSheetChrome.showsTopCancellationAction(idiom: .touch))
    }

    @Test("Desktop chrome preserves shortcuts and top confirmation")
    func desktopChrome() {
        #expect(CaptureSheetChrome.keyboardHint("T", idiom: .desktop) == "T")
        #expect(CaptureSheetChrome.keyboardHint("V", idiom: .desktop) == "V")
        #expect(CaptureSheetChrome.showsTopConfirmationAction(idiom: .desktop))
        #expect(!CaptureSheetChrome.showsTopCancellationAction(idiom: .desktop))
    }
}
