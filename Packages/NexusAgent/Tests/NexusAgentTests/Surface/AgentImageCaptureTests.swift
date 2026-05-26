import Foundation
import Testing

@testable import NexusAgent

@Test func imageCaptureEncodesAttachment() throws {
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    let payload = try AgentImageCapture.makePayload(data: png, mime: "image/png", userText: "co tu jest")
    #expect(payload.userMessage == "co tu jest")
    #expect(payload.attachments.first?.mime == "image/png")
    #expect(payload.attachments.first?.dataLength == png.count)
}

@Test func imageCaptureBuildsBase64DataURL() throws {
    let payload = try AgentImageCapture.makePayload(
        data: Data("png".utf8),
        mime: "image/png",
        userText: "inspect"
    )

    #expect(payload.attachmentDataURLs == ["data:image/png;base64,cG5n"])
}

@Test func imageCaptureParsesDataURLAttachmentPayload() throws {
    let payload = try AgentImageCapture.payload(fromDataURL: "data:image/jpeg;base64,/9j/")

    #expect(payload.mime == "image/jpeg")
    #expect(payload.data == Data([0xFF, 0xD8, 0xFF]))
}

@Test func imageCaptureRejectsEmptyData() {
    #expect(throws: AgentImageCaptureError.self) {
        _ = try AgentImageCapture.makePayload(data: Data(), mime: "image/png", userText: "x")
    }
}

@Test func imageCaptureRejectsMalformedDataURL() {
    #expect(throws: AgentImageCaptureError.malformedImageDataURL) {
        _ = try AgentImageCapture.payload(fromDataURL: "data:image/png;base64,not valid base64")
    }
}

@Test func imageCaptureRejectsNonCanonicalBase64DataURLsAcceptedByFoundation() {
    let dataURLs = [
        "data:image/png;base64,====",
        "data:image/png;base64,AAAA====",
        "data:image/png;base64,cG5n===",
        "data:image/png;base64,AB==",
        "data:image/png;base64,AAB=",
    ]

    for dataURL in dataURLs {
        #expect(throws: AgentImageCaptureError.malformedImageDataURL) {
            _ = try AgentImageCapture.payload(fromDataURL: dataURL)
        }
    }
}

@Test func imageCaptureRejectsUnsupportedMIME() {
    #expect(throws: AgentImageCaptureError.unsupportedImageMIME("image/gif")) {
        _ = try AgentImageCapture.makePayload(data: Data([0x47, 0x49, 0x46, 0x38]), mime: "image/gif", userText: "x")
    }
}

@Test func imageCaptureRejectsMultipleRuntimeDataURLAttachments() {
    #expect(throws: AgentImageCaptureError.tooManyImages(maxCount: 1, actualCount: 2)) {
        try AgentImageCapture.validateAttachmentDataURLs([
            "data:image/png;base64,cG5n",
            "data:image/jpeg;base64,/9j/",
        ])
    }
}

@Test func imageCaptureRuntimeTotalLimitMatchesSingleImageCap() {
    #expect(AgentImageCapture.maxImageAttachmentCount == 1)
    #expect(AgentImageCapture.maxTotalImageBytes == AgentImageCapture.maxImageBytes)
}

@Test func imageCaptureRejectsOversizeImage() {
    let data = Data(repeating: 0x01, count: AgentImageCapture.maxImageBytes + 1)

    #expect(
        throws: AgentImageCaptureError.imageTooLarge(
            maxBytes: AgentImageCapture.maxImageBytes,
            actualBytes: data.count
        )
    ) {
        _ = try AgentImageCapture.makePayload(data: data, mime: "image/png", userText: "x")
    }
}

@Test func imageCaptureDetectsCommonImageMIMEs() {
    #expect(AgentImageCapture.detectedMIME(for: Data([0x89, 0x50, 0x4E, 0x47])) == "image/png")
    #expect(AgentImageCapture.detectedMIME(for: Data([0xFF, 0xD8, 0xFF])) == "image/jpeg")
    #expect(AgentImageCapture.detectedMIME(for: Data([0x47, 0x49, 0x46, 0x38])) == "image/gif")
}
