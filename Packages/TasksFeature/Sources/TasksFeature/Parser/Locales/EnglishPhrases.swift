import Foundation
import NexusCore

extension LocalePhrases {
    public static let english = LocalePhrases(
        languageCode: "en",
        dayKeywords: [
            "monday": .monday, "mon": .monday,
            "tuesday": .tuesday, "tue": .tuesday, "tues": .tuesday,
            "wednesday": .wednesday, "wed": .wednesday,
            "thursday": .thursday, "thu": .thursday, "thurs": .thursday,
            "friday": .friday, "fri": .friday,
            "saturday": .saturday, "sat": .saturday,
            "sunday": .sunday, "sun": .sunday,
        ],
        relativeDays: [
            "yesterday": -1,
            "today": 0,
            "tomorrow": 1,
            "tmrw": 1,
        ],
        timeOfDay: [
            "morning": 9 * 3600,
            "noon": 12 * 3600,
            "afternoon": 15 * 3600,
            "evening": 19 * 3600,
            "night": 22 * 3600,
        ],
        recurrenceKeywords: [
            "every monday": "FREQ=WEEKLY;BYDAY=MO",
            "every tuesday": "FREQ=WEEKLY;BYDAY=TU",
            "every wednesday": "FREQ=WEEKLY;BYDAY=WE",
            "every thursday": "FREQ=WEEKLY;BYDAY=TH",
            "every friday": "FREQ=WEEKLY;BYDAY=FR",
            "every saturday": "FREQ=WEEKLY;BYDAY=SA",
            "every sunday": "FREQ=WEEKLY;BYDAY=SU",
        ],
        recurrenceFrequency: [
            "every day": "FREQ=DAILY",
            "daily": "FREQ=DAILY",
            "every week": "FREQ=WEEKLY",
            "weekly": "FREQ=WEEKLY",
            "every month": "FREQ=MONTHLY",
            "monthly": "FREQ=MONTHLY",
        ],
        relativeUnits: [
            "day": 1, "days": 1,
            "week": 7, "weeks": 7,
            "month": 30, "months": 30,
        ]
    )
}
