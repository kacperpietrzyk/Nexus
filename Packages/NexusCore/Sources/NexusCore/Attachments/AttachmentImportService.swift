import CryptoKit
import Foundation
import UniformTypeIdentifiers

public enum AttachmentImportError: Error, Equatable {
    case sourceMissing
    case directoryUnsupported
    case unsupportedImageType(String)
    case fileTooLarge(actualBytes: Int, maxBytes: Int)
}

public struct ImportedAttachmentFile: Equatable, Sendable {
    public let id: UUID
    public let originalFilename: String
    public let mimeType: String
    public let byteCount: Int
    public let sha256: String
    public let storagePath: String
    public let fileURL: URL
}

public struct AttachmentImportService {
    public static let defaultMaxImageBytes = 25 * 1_024 * 1_024

    private let root: URL
    private let maxBytes: Int
    private let fileManager: FileManager

    public init(
        root: URL,
        maxBytes: Int = Self.defaultMaxImageBytes,
        fileManager: FileManager = .default
    ) {
        self.root = root
        self.maxBytes = maxBytes
        self.fileManager = fileManager
    }

    public func importImage(from source: URL, id: UUID = UUID()) throws -> ImportedAttachmentFile {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            throw AttachmentImportError.sourceMissing
        }
        guard !isDirectory.boolValue else {
            throw AttachmentImportError.directoryUnsupported
        }

        let values = try source.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey, .localizedNameKey])
        if let fileSize = values.fileSize, fileSize > maxBytes {
            throw AttachmentImportError.fileTooLarge(actualBytes: fileSize, maxBytes: maxBytes)
        }

        let data = try Data(contentsOf: source)
        let byteCount = values.fileSize ?? data.count
        guard byteCount <= maxBytes else {
            throw AttachmentImportError.fileTooLarge(actualBytes: byteCount, maxBytes: maxBytes)
        }

        let mimeType = Self.mimeType(for: source, contentType: values.contentType)
        guard mimeType.hasPrefix("image/") else {
            throw AttachmentImportError.unsupportedImageType(mimeType)
        }

        let originalFilename = values.localizedName ?? source.lastPathComponent
        let sanitizedFilename = Self.sanitizedFilename(
            originalFilename,
            fallbackExtension: source.pathExtension
        )
        let storagePath = "attachments/\(id.uuidString)/\(sanitizedFilename)"
        let destination = root.appendingPathComponent(storagePath, isDirectory: false)

        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try data.write(to: destination, options: [.atomic])

        return ImportedAttachmentFile(
            id: id,
            originalFilename: originalFilename,
            mimeType: mimeType,
            byteCount: byteCount,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            storagePath: storagePath,
            fileURL: destination
        )
    }

    public func removeImportedFile(at storagePath: String) {
        try? fileManager.removeItem(at: root.appendingPathComponent(storagePath, isDirectory: false))
    }

    public func fileURL(for storagePath: String) -> URL {
        root.appendingPathComponent(storagePath, isDirectory: false)
    }

    static func mimeType(for source: URL, contentType: UTType?) -> String {
        if let mimeType = contentType?.preferredMIMEType {
            return mimeType
        }
        return UTType(filenameExtension: source.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
    }

    static func sanitizedFilename(_ filename: String, fallbackExtension: String) -> String {
        let base = filename.isEmpty ? "attachment" : filename
        var cleaned =
            base
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Defense-in-depth: collapse any `..` so a crafted/synced filename like
        // `../secret` cannot redirect the on-disk `attachments/<id>/` write even
        // after the separators above are neutralized.
        while cleaned.contains("..") {
            cleaned = cleaned.replacingOccurrences(of: "..", with: "_")
        }
        let safe = cleaned.isEmpty ? "attachment" : cleaned
        if safe.contains(".") || fallbackExtension.isEmpty {
            return safe
        }
        return "\(safe).\(fallbackExtension)"
    }
}
