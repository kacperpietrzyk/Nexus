import Foundation

public enum ReadinessRowState: Sendable, Equatable {
    case ok
    case warning
    case error
    case info
    case inProgress
}

public enum ReadinessRowAction: Sendable, Equatable {
    case requestMicrophone
    case openAccessibilitySettings
    case downloadModel(MeetingsModelID)
    case downloadAllModels
    case startHelper
    case enableAutoRecord
    case info(String)
}

public struct ReadinessRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String?
    public let state: ReadinessRowState
    public let action: ReadinessRowAction?
}

public enum ReadinessSectionID: String, Sendable, Equatable {
    case permissions
    case models
    case environment
}

public struct ReadinessSection: Sendable, Equatable, Identifiable {
    public let id: ReadinessSectionID
    public let title: String
    public let rows: [ReadinessRow]
}

public struct ReadinessRowMapper: Sendable {
    private let stalenessThreshold: TimeInterval

    public init(stalenessThreshold: TimeInterval = 120) {
        self.stalenessThreshold = stalenessThreshold
    }

    public func sections(from snapshot: MeetingsReadinessSnapshot?, now: Date) -> [ReadinessSection] {
        [
            permissionsSection(snapshot),
            modelsSection(snapshot),
            environmentSection(snapshot, now: now),
        ]
    }

    private func permissionsSection(_ snapshot: MeetingsReadinessSnapshot?) -> ReadinessSection {
        let permissions = snapshot?.permissions
        return ReadinessSection(
            id: .permissions, title: "Permissions",
            rows: [
                ReadinessRow(
                    id: "permission.microphone",
                    title: "Microphone",
                    detail: nil,
                    state: state(for: permissions?.microphone),
                    action: .requestMicrophone
                ),
                ReadinessRow(
                    id: "permission.accessibility",
                    title: "Accessibility",
                    detail: "Needed to detect meeting windows.",
                    state: state(for: permissions?.accessibility),
                    action: .openAccessibilitySettings
                ),
                ReadinessRow(
                    id: "permission.audioCapture",
                    title: "System audio",
                    detail: "Prompts on first recording.",
                    state: permissions?.audioCapture == .granted ? .ok : .info,
                    action: .info("System audio access is requested the first time a recording starts.")
                ),
            ])
    }

    private func modelsSection(_ snapshot: MeetingsReadinessSnapshot?) -> ReadinessSection {
        let titles: [MeetingsModelID: String] = [
            .parakeet: "Parakeet (transcription)",
            .sortformer: "Sortformer (speaker separation)",
            .whisperKit: "WhisperKit (fallback)",
        ]
        var rows = MeetingsModelID.allCases.map { id -> ReadinessRow in
            let model = snapshot?.models.first { $0.id == id }
            return ReadinessRow(
                id: "model.\(id.rawValue)",
                title: titles[id] ?? id.rawValue,
                detail: nil,
                state: state(for: model?.state),
                action: .downloadModel(id)
            )
        }
        rows.append(
            ReadinessRow(
                id: "model.downloadAll",
                title: "Download all models",
                detail: nil,
                state: .info,
                action: .downloadAllModels
            ))
        return ReadinessSection(id: .models, title: "Models", rows: rows)
    }

    private func environmentSection(_ snapshot: MeetingsReadinessSnapshot?, now: Date) -> ReadinessSection {
        let isLive: Bool = {
            guard let snapshot else { return false }
            return now.timeIntervalSince(snapshot.lastUpdated) <= stalenessThreshold
        }()
        var rows: [ReadinessRow] = []
        rows.append(
            ReadinessRow(
                id: "env.macOS",
                title: "macOS compatible",
                detail: snapshot?.environment.macOSCompatible == false ? "Requires macOS 14.4 or newer." : nil,
                state: snapshot?.environment.macOSCompatible == true ? .ok : .warning,
                action: nil
            ))
        rows.append(
            ReadinessRow(
                id: "env.helper",
                title: "Helper running",
                detail: isLive ? nil : "The Meetings helper is not running.",
                state: isLive ? .ok : .error,
                action: isLive ? nil : .startHelper
            ))
        rows.append(
            ReadinessRow(
                id: "env.autoRecord",
                title: "Auto-record enabled",
                detail: nil,
                state: snapshot?.environment.autoRecordEnabled == true ? .ok : .warning,
                action: snapshot?.environment.autoRecordEnabled == true ? nil : .enableAutoRecord
            ))
        return ReadinessSection(id: .environment, title: "Environment", rows: rows)
    }

    private func state(for permission: PermissionState?) -> ReadinessRowState {
        switch permission {
        case .granted: .ok
        case .denied: .error
        case .notDetermined, .unknown, nil: .warning
        case .unsupported: .warning
        }
    }

    private func state(for model: ModelDownloadState?) -> ReadinessRowState {
        switch model {
        case .ready: .ok
        case .downloading: .inProgress
        case .failed: .error
        case .absent, nil: .warning
        }
    }
}
