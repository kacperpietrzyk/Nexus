import Foundation
import NexusSync

public enum MeetingAudioRootResolver {
    private static let appSupportDirectoryName = "com.kacperpietrzyk.Nexus"
    private static let sharedDirectoryName = "Nexus"
    private static let meetingsDirectoryName = "Meetings"

    public static func rootFolder(
        appGroupIdentifier: String = NexusModelContainer.appGroupIdentifier,
        fileManager: FileManager = .default
    ) -> URL {
        let applicationSupportURL =
            (try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ))
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let groupContainerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
        let root = resolveRootFolder(
            groupContainerURL: groupContainerURL,
            applicationSupportURL: applicationSupportURL
        )
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func resolveRootFolder(groupContainerURL: URL?, applicationSupportURL: URL) -> URL {
        if let groupContainerURL {
            return
                groupContainerURL
                .appendingPathComponent(sharedDirectoryName, isDirectory: true)
                .appendingPathComponent(meetingsDirectoryName, isDirectory: true)
        }

        return
            applicationSupportURL
            .appendingPathComponent(appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent(meetingsDirectoryName, isDirectory: true)
    }
}
