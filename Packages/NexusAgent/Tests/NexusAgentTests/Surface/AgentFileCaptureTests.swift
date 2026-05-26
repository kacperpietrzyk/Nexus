import Foundation
import Testing

@testable import NexusAgent

#if canImport(CoreGraphics) && canImport(CoreText) && canImport(PDFKit)
import CoreGraphics
import CoreText
import PDFKit
#endif

@Test func fileCaptureReadsPlainText() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "x.txt")
    try "hello".write(to: url, atomically: true, encoding: .utf8)

    let result = try AgentFileCapture.extract(from: url)

    #expect(result.text == "hello")
    #expect(result.kind == .text)
    #expect(result.sourceFilename == "x.txt")
}

@Test func fileCaptureRejectsUnknownExtension() {
    let url = URL(filePath: "/tmp/whatever.unknownext")

    #expect(throws: AgentFileCaptureError.self) {
        _ = try AgentFileCapture.extract(from: url)
    }
}

@Test func fileCaptureRejectsOversizeFile() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "large.txt")
    let data = Data(repeating: 0x61, count: AgentFileCapture.maxFileBytes + 1)
    try data.write(to: url)

    #expect(throws: AgentFileCaptureError.self) {
        _ = try AgentFileCapture.extract(from: url)
    }
}

@Test func fileCaptureRejectsOversizeExtractedText() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "many-characters.txt")
    let text = String(repeating: "a", count: AgentFileCapture.maxExtractedCharacters + 1)
    try text.write(to: url, atomically: true, encoding: .utf8)

    #expect(throws: AgentFileCaptureError.self) {
        _ = try AgentFileCapture.extract(from: url)
    }
}

@Test func fileCapturePDFAccumulatorRejectsBeforeAppendingOversizePage() throws {
    var accumulated = String(repeating: "a", count: AgentFileCapture.maxExtractedCharacters - 2)
    let original = accumulated

    #expect(throws: AgentFileCaptureError.self) {
        try AgentFileCapture.appendPDFPageText("bb", to: &accumulated)
    }
    #expect(accumulated == original)
}

@Test func fileCapturePDFAccumulatorJoinsPagesIncrementally() throws {
    var accumulated = ""

    try AgentFileCapture.appendPDFPageText("first", to: &accumulated)
    try AgentFileCapture.appendPDFPageText(nil, to: &accumulated)
    try AgentFileCapture.appendPDFPageText("second", to: &accumulated)

    #expect(accumulated == "first\nsecond")
}

@Test func fileCaptureReadsSwiftSourceAsCode() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "Example.swift")
    try "let value = 42\n".write(to: url, atomically: true, encoding: .utf8)

    let result = try AgentFileCapture.extract(from: url)

    #expect(result.kind == .code(language: "swift"))
    #expect(result.text == "let value = 42\n")
}

@Test func fileCaptureFormatsSystemPrefixWithCodeFence() {
    let result = AgentFileCaptureResult(
        kind: .code(language: "swift"),
        text: "let value = 42",
        sourceFilename: "Example.swift"
    )

    let prefix = AgentFileCapture.formatSystemPrefix(result)

    #expect(prefix.contains("[System context from attached file \"Example.swift\"]"))
    #expect(prefix.contains("```swift\nlet value = 42\n```"))
    #expect(prefix.contains("[/System context]"))
}

@Test func fileCaptureJoinsNonEmptyContextPrefixes() {
    let context = AgentFileCapture.joinContextPrefixes(
        ["[System context]\nhello\n[/System context]"]
    )

    #expect(
        context
            == """
            [System context]
            hello
            [/System context]
            """
    )
}

#if canImport(CoreGraphics) && canImport(CoreText) && canImport(PDFKit)
@Test func fileCaptureExtractsPDFText() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "capture.pdf")
    try makeTextPDF(text: "hello from pdf", url: url)

    let result = try AgentFileCapture.extract(from: url)

    #expect(result.kind == .pdf)
    #expect(result.text.contains("hello from pdf"))
}

@Test func fileCaptureRejectsEmptyPDFText() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "empty.pdf")
    try makeEmptyPDF(url: url)

    #expect(throws: AgentFileCaptureError.self) {
        _ = try AgentFileCapture.extract(from: url)
    }
}

private func makeEmptyPDF(url: URL) throws {
    var mediaBox = CGRect(x: 0, y: 0, width: 300, height: 120)
    guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
        Issue.record("Could not create PDF context")
        return
    }

    context.beginPDFPage(nil)
    context.endPDFPage()
    context.closePDF()
}

private func makeTextPDF(text: String, url: URL) throws {
    var mediaBox = CGRect(x: 0, y: 0, width: 300, height: 120)
    guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
        Issue.record("Could not create PDF context")
        return
    }

    context.beginPDFPage(nil)
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 18, nil)
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let line = CTLineCreateWithAttributedString(attributed)
    context.textPosition = CGPoint(x: 24, y: 60)
    CTLineDraw(line, context)
    context.endPDFPage()
    context.closePDF()
}
#endif
