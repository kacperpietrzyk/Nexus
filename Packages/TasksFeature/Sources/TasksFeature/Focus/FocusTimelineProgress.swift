import Foundation

enum FocusTimelineProgress {
    static func progress(startAt: Date?, endAt: Date?, dueAt: Date?, now: Date) -> Double {
        guard let startAt else { return 0 }
        guard let finish = endAt ?? dueAt, finish > startAt else {
            return now >= startAt ? 1 : 0
        }
        guard now > startAt else { return 0 }
        guard now < finish else { return 1 }
        return now.timeIntervalSince(startAt) / finish.timeIntervalSince(startAt)
    }

    static func elapsedMinutes(startAt: Date?, now: Date) -> Int {
        guard let startAt, now > startAt else { return 0 }
        return max(0, Int(now.timeIntervalSince(startAt) / 60))
    }
}
