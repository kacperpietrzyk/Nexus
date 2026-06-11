import Foundation
import NexusCore
import Testing

@testable import TasksFeature

@Suite("RoadmapModel time-axis geometry")
struct RoadmapGeometryTests {

    // MARK: - Fixtures

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private static let warsaw: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private static func date(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar = utc) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private static func bar(start: Date, end: Date?, milestones: [RoadmapModel.MilestoneMarker] = []) -> RoadmapModel.ProjectBar {
        RoadmapModel.ProjectBar(
            projectID: UUID(),
            name: "P",
            glyphToken: "azure",
            start: start,
            end: end,
            health: .onTrack,
            progress: 0,
            milestones: milestones
        )
    }

    private static func milestone(date: Date) -> RoadmapModel.MilestoneMarker {
        RoadmapModel.MilestoneMarker(sectionID: UUID(), title: "M", date: date, state: .upcoming)
    }

    // MARK: - Window

    @Test("Window pads 7 days before the earliest date and 14 after the latest, day-snapped")
    func windowPadding() {
        let bars = [
            Self.bar(
                start: Self.date(2026, 6, 10),
                end: Self.date(2026, 6, 20),
                milestones: [Self.milestone(date: Self.date(2026, 6, 25))]
            )
        ]

        let window = RoadmapModel.window(bars: bars, cycles: [], now: Self.date(2026, 6, 11), calendar: Self.utc)

        #expect(window.start == Self.date(2026, 6, 3))
        #expect(window.end == Self.date(2026, 7, 9))
    }

    @Test("Open-ended bars fall back to now as the latest anchor; cycles stretch the window")
    func windowCoversCyclesAndNow() {
        let bars = [Self.bar(start: Self.date(2026, 6, 1), end: nil)]
        let cycles = [
            RoadmapModel.CycleBar(
                cycleID: UUID(),
                name: "S1",
                startAt: Self.date(2026, 5, 25),
                endAt: Self.date(2026, 6, 30),
                status: .active
            )
        ]

        let window = RoadmapModel.window(bars: bars, cycles: cycles, now: Self.date(2026, 6, 11), calendar: Self.utc)

        #expect(window.start == Self.date(2026, 5, 18))
        #expect(window.end == Self.date(2026, 7, 14))

        let empty = RoadmapModel.window(bars: [], cycles: [], now: Self.date(2026, 6, 11), calendar: Self.utc)
        #expect(empty.start == Self.date(2026, 6, 4))
        #expect(empty.end == Self.date(2026, 6, 25))
    }

    // MARK: - Date to X

    @Test("xOffset is whole calendar days times the zoom scale")
    func xOffsetMath() {
        let window = DateInterval(start: Self.date(2026, 6, 3), end: Self.date(2026, 7, 4))

        let x = RoadmapModel.xOffset(for: Self.date(2026, 6, 10), in: window, zoom: .week, calendar: Self.utc)

        #expect(x == 7 * RoadmapModel.Zoom.week.pointsPerDay)
        #expect(RoadmapModel.xOffset(for: window.start, in: window, zoom: .month, calendar: Self.utc) == 0)
    }

    @Test("DST spring-forward does not shear the axis")
    func xOffsetAcrossDST() {
        let window = DateInterval(
            start: Self.date(2026, 3, 27, in: Self.warsaw),
            end: Self.date(2026, 4, 30, in: Self.warsaw)
        )

        let x = RoadmapModel.xOffset(
            for: Self.date(2026, 3, 31, in: Self.warsaw),
            in: window,
            zoom: .month,
            calendar: Self.warsaw
        )

        #expect(x == 4 * RoadmapModel.Zoom.month.pointsPerDay)
    }

    @Test("Bar width never collapses below one day; content width spans the window")
    func widths() {
        let day = Self.date(2026, 6, 10)

        #expect(
            RoadmapModel.barWidth(from: day, to: day, zoom: .quarter, calendar: Self.utc)
                == RoadmapModel.Zoom.quarter.pointsPerDay
        )
        #expect(
            RoadmapModel.barWidth(from: day, to: Self.date(2026, 6, 13), zoom: .week, calendar: Self.utc)
                == 3 * RoadmapModel.Zoom.week.pointsPerDay
        )

        let window = DateInterval(start: Self.date(2026, 6, 3), end: Self.date(2026, 7, 4))
        #expect(
            RoadmapModel.contentWidth(window: window, zoom: .month, calendar: Self.utc)
                == 31 * RoadmapModel.Zoom.month.pointsPerDay
        )
    }

    // MARK: - Ticks

    @Test("Week zoom ticks on week starts inside the window")
    func weekTicks() {
        let window = DateInterval(start: Self.date(2026, 6, 3), end: Self.date(2026, 7, 4))

        let ticks = RoadmapModel.ticks(in: window, zoom: .week, calendar: Self.utc)

        #expect(
            ticks == [
                Self.date(2026, 6, 8),
                Self.date(2026, 6, 15),
                Self.date(2026, 6, 22),
                Self.date(2026, 6, 29),
            ])
    }

    @Test("Month zoom ticks on month firsts; quarter zoom keeps only Jan/Apr/Jul/Oct")
    func monthAndQuarterTicks() {
        let window = DateInterval(start: Self.date(2026, 6, 3), end: Self.date(2026, 11, 20))

        let months = RoadmapModel.ticks(in: window, zoom: .month, calendar: Self.utc)
        #expect(
            months == [
                Self.date(2026, 7, 1),
                Self.date(2026, 8, 1),
                Self.date(2026, 9, 1),
                Self.date(2026, 10, 1),
                Self.date(2026, 11, 1),
            ])

        let quarters = RoadmapModel.ticks(in: window, zoom: .quarter, calendar: Self.utc)
        #expect(quarters == [Self.date(2026, 7, 1), Self.date(2026, 10, 1)])
    }

    // MARK: - Labels

    @Test("Health labels are the execution-screen vocabulary")
    func healthLabels() {
        #expect(RoadmapModel.healthLabel(.onTrack) == "On Track")
        #expect(RoadmapModel.healthLabel(.atRisk) == "At Risk")
        #expect(RoadmapModel.healthLabel(.offTrack) == "Off Track")
    }
}
