import Foundation

#if canImport(PDFKit)
import PDFKit
#endif

public enum AgentFileCaptureError: Error, Equatable {
    case unsupportedExtension(String)
    case fileTooLarge(maxBytes: Int, actualBytes: Int)
    case extractedTextTooLarge(maxCharacters: Int, actualCharacters: Int)
    case readFailed(String)
}

public enum AgentFileKind: Equatable, Sendable {
    case text
    case code(language: String)
    case pdf
}

public struct AgentFileCaptureResult: Equatable, Sendable {
    public let kind: AgentFileKind
    public let text: String
    public let sourceFilename: String

    public init(kind: AgentFileKind, text: String, sourceFilename: String) {
        self.kind = kind
        self.text = text
        self.sourceFilename = sourceFilename
    }
}

public enum AgentFileCapture {
    public static let maxFileBytes = 2 * 1024 * 1024
    public static let maxExtractedCharacters = 120_000

    public static func extract(from url: URL) throws -> AgentFileCaptureResult {
        let fileExtension = normalizedExtension(for: url)
        let filename = url.lastPathComponent

        if fileExtension == "pdf" {
            try validateFileSize(url)
            let text = try validateExtractedText(
                extractPDFText(from: url),
                sourceDescription: "PDF",
                rejectEmpty: true
            )
            return AgentFileCaptureResult(
                kind: .pdf,
                text: text,
                sourceFilename: filename
            )
        }

        if textExtensions.contains(fileExtension) {
            try validateFileSize(url)
            let text = try validateExtractedText(
                readUTF8Text(from: url),
                sourceDescription: "Text file",
                rejectEmpty: false
            )
            return AgentFileCaptureResult(
                kind: .text,
                text: text,
                sourceFilename: filename
            )
        }

        if let language = codeLanguages[fileExtension] {
            try validateFileSize(url)
            let text = try validateExtractedText(
                readUTF8Text(from: url),
                sourceDescription: "Source file",
                rejectEmpty: false
            )
            return AgentFileCaptureResult(
                kind: .code(language: language),
                text: text,
                sourceFilename: filename
            )
        }

        throw AgentFileCaptureError.unsupportedExtension(fileExtension)
    }

    public static func formatSystemPrefix(_ result: AgentFileCaptureResult) -> String {
        let language = fenceLanguage(for: result.kind)
        return """
            [System context from attached file "\(result.sourceFilename)"]
            ```\(language)
            \(result.text)
            ```
            [/System context]
            """
    }

    public static func joinContextPrefixes(_ fileContextPrefixes: [String]) -> String? {
        let prefixes =
            fileContextPrefixes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return prefixes.isEmpty ? nil : prefixes.joined(separator: "\n\n")
    }

    public static func userFacingErrorMessage(for error: Error) -> String {
        guard let captureError = error as? AgentFileCaptureError else {
            return "File attachment failed."
        }

        switch captureError {
        case .unsupportedExtension(let fileExtension):
            return fileExtension.isEmpty
                ? "File type is not supported."
                : "File type .\(fileExtension) is not supported."
        case .fileTooLarge:
            return "File is too large."
        case .extractedTextTooLarge:
            return "Extracted file text is too large."
        case .readFailed:
            return "File could not be read."
        }
    }
}

extension AgentFileCapture {
    private static let textExtensions: Set<String> = [
        "markdown",
        "md",
        "text",
        "txt",
    ]

    private static let codeLanguages: [String: String] = [
        "bash": "bash",
        "c": "c",
        "cc": "cpp",
        "cpp": "cpp",
        "cs": "csharp",
        "css": "css",
        "go": "go",
        "h": "c",
        "hpp": "cpp",
        "html": "html",
        "java": "java",
        "js": "javascript",
        "json": "json",
        "kt": "kotlin",
        "m": "objective-c",
        "mm": "objective-cpp",
        "py": "python",
        "rb": "ruby",
        "rs": "rust",
        "sh": "bash",
        "sql": "sql",
        "swift": "swift",
        "ts": "typescript",
        "xml": "xml",
        "yaml": "yaml",
        "yml": "yaml",
        "zsh": "zsh",
    ]

    private static func normalizedExtension(for url: URL) -> String {
        url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func readUTF8Text(from url: URL) throws -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw AgentFileCaptureError.readFailed(error.localizedDescription)
        }
    }

    private static func validateFileSize(_ url: URL) throws {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.fileSizeKey])
        } catch {
            throw AgentFileCaptureError.readFailed(error.localizedDescription)
        }

        guard let fileSize = values.fileSize else {
            throw AgentFileCaptureError.readFailed("Could not determine file size.")
        }

        guard fileSize <= maxFileBytes else {
            throw AgentFileCaptureError.fileTooLarge(maxBytes: maxFileBytes, actualBytes: fileSize)
        }
    }

    private static func validateExtractedText(
        _ text: String,
        sourceDescription: String,
        rejectEmpty: Bool
    ) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rejectEmpty || !trimmed.isEmpty else {
            throw AgentFileCaptureError.readFailed("\(sourceDescription) did not contain extractable text.")
        }

        guard text.count <= maxExtractedCharacters else {
            throw AgentFileCaptureError.extractedTextTooLarge(
                maxCharacters: maxExtractedCharacters,
                actualCharacters: text.count
            )
        }

        return text
    }

    private static func extractPDFText(from url: URL) throws -> String {
        #if canImport(PDFKit)
        guard let document = PDFDocument(url: url) else {
            throw AgentFileCaptureError.readFailed("PDFKit could not open \(url.lastPathComponent).")
        }

        var accumulatedText = ""
        for pageIndex in 0..<document.pageCount {
            try appendPDFPageText(document.page(at: pageIndex)?.string, to: &accumulatedText)
        }
        return accumulatedText
        #else
        throw AgentFileCaptureError.readFailed("PDFKit is unavailable on this platform.")
        #endif
    }

    static func appendPDFPageText(_ pageText: String?, to accumulatedText: inout String) throws {
        guard let pageText else { return }

        let separatorCount = accumulatedText.isEmpty ? 0 : 1
        let actualCharacters = accumulatedText.count + separatorCount + pageText.count
        guard actualCharacters <= maxExtractedCharacters else {
            throw AgentFileCaptureError.extractedTextTooLarge(
                maxCharacters: maxExtractedCharacters,
                actualCharacters: actualCharacters
            )
        }

        if separatorCount == 1 {
            accumulatedText.append("\n")
        }
        accumulatedText.append(pageText)
    }

    private static func fenceLanguage(for kind: AgentFileKind) -> String {
        switch kind {
        case .text, .pdf:
            "text"
        case .code(let language):
            language
        }
    }
}
