import Foundation

public struct AppPattern: Sendable, Codable, Equatable {
    public let bundleID: String
    public let displayName: String
    public let regex: String
    public var enabled: Bool

    public init(bundleID: String, displayName: String, regex: String, enabled: Bool = true) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.regex = regex
        self.enabled = enabled
    }
}

public struct AppPatternRegistry: Sendable, Codable, Equatable {
    public private(set) var patterns: [AppPattern]

    public init(patterns: [AppPattern]) {
        self.patterns = patterns
    }

    public static func makeDefault() -> AppPatternRegistry {
        AppPatternRegistry(patterns: [
            .init(
                bundleID: "com.microsoft.teams2", displayName: "Microsoft Teams",
                regex: #"(?i)(microsoft teams.*meeting|waiting for the meeting to start|lobby.*teams|teams.*lobby)"#),
            .init(
                bundleID: "com.microsoft.teams", displayName: "Microsoft Teams (legacy)",
                regex: #"(?i)(microsoft teams.*meeting|waiting for the meeting to start|lobby.*teams|teams.*lobby)"#),
            .init(
                bundleID: "us.zoom.xos", displayName: "Zoom",
                regex: #"(?i)(^Zoom Meeting|Waiting Room|^Zoom - (?!Mail).+)"#),
            .init(
                bundleID: "Cisco-Systems.Spark", displayName: "Cisco Webex",
                regex: #"(?i)(Cisco Webex Meeting|Webex Meeting)"#),
        ])
    }

    public func matches(bundleID: String, title: String) -> Bool {
        patterns
            .filter { $0.bundleID == bundleID && $0.enabled }
            .contains { title.range(of: $0.regex, options: .regularExpression) != nil }
    }

    public mutating func setEnabled(_ bundleID: String, enabled: Bool) {
        for idx in patterns.indices where patterns[idx].bundleID == bundleID {
            patterns[idx].enabled = enabled
        }
    }

    public mutating func append(_ pattern: AppPattern) {
        patterns.append(pattern)
    }

    /// Stable identifier for debouncing per detected meeting.
    public func fingerprint(bundleID: String, title: String) -> String {
        "\(bundleID)|\(normalizedTitle(title))"
    }

    public func normalizedTitle(_ title: String) -> String {
        title
            .replacingOccurrences(
                of: #"\s*—\s*Microsoft Teams.*$"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\s*\|\s*Microsoft Teams.*$"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\s*—\s*Zoom.*$"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\s*\|\s*Zoom.*$"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\s*—\s*[A-Za-z0-9][A-Za-z0-9-]{2,}$"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
