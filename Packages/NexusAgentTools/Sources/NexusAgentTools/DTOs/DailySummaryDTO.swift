import Foundation

public struct DailySummaryDTO: Codable, Sendable, Equatable {
    public let heroBrief: String
    public let today: [TaskDTO]
    public let upcoming: [TaskDTO]
    public let focusBuckets: FocusBucketsDTO

    private enum CodingKeys: String, CodingKey {
        case today, upcoming
        case heroBrief = "hero_brief"
        case focusBuckets = "focus_buckets"
    }

    public init(heroBrief: String, today: [TaskDTO], upcoming: [TaskDTO], focusBuckets: FocusBucketsDTO) {
        self.heroBrief = heroBrief
        self.today = today
        self.upcoming = upcoming
        self.focusBuckets = focusBuckets
    }
}

public struct FocusBucketsDTO: Codable, Sendable, Equatable {
    public let am: [TaskDTO]
    public let pm: [TaskDTO]
    public let evening: [TaskDTO]

    public init(am: [TaskDTO], pm: [TaskDTO], evening: [TaskDTO]) {
        self.am = am
        self.pm = pm
        self.evening = evening
    }
}
