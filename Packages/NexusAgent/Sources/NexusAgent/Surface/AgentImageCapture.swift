import Foundation

public enum AgentImageCaptureError: Error, Equatable {
    case emptyImage
    case malformedImageDataURL
    case noCloudProviderConsented
    case tooManyImages(maxCount: Int, actualCount: Int)
    case imageTooLarge(maxBytes: Int, actualBytes: Int)
    case imageTotalTooLarge(maxBytes: Int, actualBytes: Int)
    case unsupportedImageMIME(String)
}

public struct AgentAttachmentPayload: Sendable, Equatable {
    public let mime: String
    public let data: Data

    public init(mime: String, data: Data) {
        self.mime = mime
        self.data = data
    }

    public var dataLength: Int {
        data.count
    }

    public var dataURL: String {
        "data:\(mime);base64,\(data.base64EncodedString())"
    }
}

public struct AgentImageMessagePayload: Sendable, Equatable {
    public let userMessage: String
    public let attachments: [AgentAttachmentPayload]

    public init(userMessage: String, attachments: [AgentAttachmentPayload]) {
        self.userMessage = userMessage
        self.attachments = attachments
    }

    public var attachmentDataURLs: [String] {
        attachments.map(\.dataURL)
    }
}

public enum AgentImageCapture {
    public static let maxImageAttachmentCount = 1
    public static let maxImageBytes = 8 * 1024 * 1024
    public static let maxTotalImageBytes = maxImageBytes
    public static let supportedImageMIMEs: Set<String> = ["image/png", "image/jpeg"]

    public static func makePayload(
        data: Data,
        mime: String,
        userText: String
    ) throws -> AgentImageMessagePayload {
        guard !data.isEmpty else {
            throw AgentImageCaptureError.emptyImage
        }

        guard data.count <= maxImageBytes else {
            throw AgentImageCaptureError.imageTooLarge(maxBytes: maxImageBytes, actualBytes: data.count)
        }

        let normalizedMIME = normalizedMIME(mime)
        guard supportedImageMIMEs.contains(normalizedMIME) else {
            throw AgentImageCaptureError.unsupportedImageMIME(normalizedMIME)
        }

        return AgentImageMessagePayload(
            userMessage: userText,
            attachments: [
                AgentAttachmentPayload(
                    mime: normalizedMIME,
                    data: data
                )
            ]
        )
    }

    public static func makeDataURL(data: Data, mime: String) throws -> String {
        try makePayload(data: data, mime: mime, userText: "").attachments[0].dataURL
    }

    public static func validateAttachmentDataURLs(_ attachments: [String]) throws {
        guard attachments.count <= maxImageAttachmentCount else {
            throw AgentImageCaptureError.tooManyImages(
                maxCount: maxImageAttachmentCount,
                actualCount: attachments.count
            )
        }

        var totalBytes = 0
        for attachment in attachments {
            let payload = try payload(fromDataURL: attachment)
            totalBytes += payload.dataLength
            guard totalBytes <= maxTotalImageBytes else {
                throw AgentImageCaptureError.imageTotalTooLarge(
                    maxBytes: maxTotalImageBytes,
                    actualBytes: totalBytes
                )
            }
        }
    }

    public static func payload(fromDataURL dataURL: String) throws -> AgentAttachmentPayload {
        guard dataURL.hasPrefix("data:") else {
            throw AgentImageCaptureError.malformedImageDataURL
        }

        let body = dataURL.dropFirst("data:".count)
        guard let comma = body.firstIndex(of: ",") else {
            throw AgentImageCaptureError.malformedImageDataURL
        }

        let metadata = body[..<comma]
        let encoded = body[body.index(after: comma)...]
        let metadataParts = metadata.split(separator: ";", omittingEmptySubsequences: false)
        guard metadataParts.count == 2,
            metadataParts[1] == "base64"
        else {
            throw AgentImageCaptureError.malformedImageDataURL
        }

        let mime = normalizedMIME(String(metadataParts[0]))
        guard supportedImageMIMEs.contains(mime) else {
            throw AgentImageCaptureError.unsupportedImageMIME(mime)
        }

        let encodedLength = encoded.utf8.count
        let maxEncodedLength = ((maxImageBytes + 2) / 3) * 4
        guard encodedLength <= maxEncodedLength else {
            throw AgentImageCaptureError.imageTooLarge(maxBytes: maxImageBytes, actualBytes: maxImageBytes + 1)
        }

        guard isCanonicalBase64(encoded) else {
            throw AgentImageCaptureError.malformedImageDataURL
        }

        let encodedString = String(encoded)
        guard let data = Data(base64Encoded: encodedString),
            data.base64EncodedString() == encodedString
        else {
            throw AgentImageCaptureError.malformedImageDataURL
        }

        return try makePayload(data: data, mime: mime, userText: "").attachments[0]
    }

    public static func normalizedMIME(_ mime: String) -> String {
        let trimmed = mime.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "application/octet-stream" : trimmed.lowercased()
    }

    public static func userFacingErrorMessage(for error: Error) -> String {
        guard let captureError = error as? AgentImageCaptureError else {
            return "Image attachment failed."
        }

        switch captureError {
        case .emptyImage:
            return "Image file is empty."
        case .malformedImageDataURL:
            return "Image attachment is invalid."
        case .noCloudProviderConsented:
            return "Image attachments arrive with on-device AI in the next phase."
        case .tooManyImages:
            return "Only one image attachment is supported."
        case .imageTooLarge:
            return "Image attachment is too large."
        case .imageTotalTooLarge:
            return "Image attachments are too large."
        case .unsupportedImageMIME:
            return "Image type is not supported."
        }
    }

    public static func detectedMIME(for data: Data, fallback: String = "image/png") -> String {
        guard !data.isEmpty else { return fallback }

        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "image/png"
        }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "image/jpeg"
        }
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) {
            return "image/gif"
        }

        let isHEIC =
            bytes.count >= 12
            && Array(bytes[4...7]) == [0x66, 0x74, 0x79, 0x70]
            && Array(bytes[8...11]) == [0x68, 0x65, 0x69, 0x63]
        if isHEIC {
            return "image/heic"
        }
        return normalizedMIME(fallback)
    }

    private static func isCanonicalBase64(_ encoded: Substring) -> Bool {
        guard !encoded.isEmpty,
            encoded.count.isMultiple(of: 4)
        else {
            return false
        }

        let paddingCount = encoded.reversed().prefix { $0 == "=" }.count
        guard paddingCount <= 2 else {
            return false
        }

        let unpaddedEnd = encoded.index(encoded.endIndex, offsetBy: -paddingCount)
        let unpadded = encoded[..<unpaddedEnd]

        guard unpadded.allSatisfy(isBase64Alphabet) else {
            return false
        }

        return encoded[unpaddedEnd...].allSatisfy { $0 == "=" }
    }

    private static func isBase64Alphabet(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
            let scalar = character.unicodeScalars.first
        else {
            return false
        }

        switch scalar.value {
        case 65...90, 97...122, 48...57, 43, 47:
            return true
        default:
            return false
        }
    }
}
