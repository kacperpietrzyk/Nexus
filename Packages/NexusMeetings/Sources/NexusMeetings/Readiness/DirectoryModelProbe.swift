import Foundation

public struct DirectoryModelProbe: ModelProbing {
    public struct Resolver: Sendable {
        public let id: MeetingsModelID
        public let folder: @Sendable () -> URL?

        public init(id: MeetingsModelID, folder: @escaping @Sendable () -> URL?) {
            self.id = id
            self.folder = folder
        }
    }

    private let resolvers: [Resolver]
    // FileManager is not Sendable; we only use the thread-safe singleton path.
    private nonisolated(unsafe) let fileManager: FileManager

    public init(resolvers: [Resolver], fileManager: FileManager = .default) {
        self.resolvers = resolvers
        self.fileManager = fileManager
    }

    public func currentModels() -> [ModelReadiness] {
        resolvers.map { resolver in
            guard let folder = resolver.folder(), let size = totalSize(of: folder), size > 0 else {
                return ModelReadiness(id: resolver.id, sizeBytes: nil, state: .absent)
            }
            return ModelReadiness(id: resolver.id, sizeBytes: size, state: .ready)
        }
    }

    private func totalSize(of folder: URL) -> Int64? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        guard
            let enumerator = fileManager.enumerator(
                at: folder,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
            )
        else {
            return nil
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }
}
