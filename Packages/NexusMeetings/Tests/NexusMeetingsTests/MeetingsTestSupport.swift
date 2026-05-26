import Foundation
import NexusSync
import SwiftData

@testable import NexusMeetings

enum MeetingsTestSupport {
    @MainActor
    static func makeContainer() throws -> ModelContainer {
        try NexusModelContainer.makeInMemory(
            extraModels: [Meeting.self],
            localOnlyExtraModels: [MeetingAudioStorage.self]
        )
    }

    @MainActor
    static func makeContext() throws -> ModelContext {
        ModelContext(try makeContainer())
    }

    static func bundleURL(forFixture name: String) throws -> URL {
        guard
            let url = Bundle.module.url(
                forResource: name,
                withExtension: nil,
                subdirectory: "Fixtures"
            )
        else {
            throw NSError(
                domain: "MeetingsTestSupport",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Fixture not found: \(name)"]
            )
        }
        return url
    }

    static func meeting(
        title: String = "Test meeting",
        startedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        durationSec: Int = 1800,
        source: MeetingDetectionSource = .auto,
        status: MeetingProcessingStatus = .recording,
        transcript: String = "",
        summary: String = ""
    ) -> Meeting {
        Meeting(
            title: title,
            startedAt: startedAt,
            durationSec: durationSec,
            appBundleID: "com.microsoft.teams2",
            detectionSource: source,
            processingStatus: status,
            transcriptText: transcript,
            summaryText: summary
        )
    }
}
