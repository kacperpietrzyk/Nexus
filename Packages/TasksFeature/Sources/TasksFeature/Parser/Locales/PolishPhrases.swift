import Foundation
import NexusCore

extension LocalePhrases {
    public static let polish = LocalePhrases(
        languageCode: "pl",
        dayKeywords: [
            "poniedziałek": .monday, "pon": .monday,
            "wtorek": .tuesday, "wt": .tuesday,
            "środa": .wednesday, "śr": .wednesday,
            "czwartek": .thursday, "czw": .thursday,
            "piątek": .friday, "pt": .friday,
            "sobota": .saturday, "sob": .saturday,
            "niedziela": .sunday, "nd": .sunday,
        ],
        relativeDays: [
            "wczoraj": -1,
            "dziś": 0, "dzisiaj": 0,
            "jutro": 1,
            "pojutrze": 2,
        ],
        timeOfDay: [
            "rano": 9 * 3600,
            "w południe": 12 * 3600,
            "popołudniu": 15 * 3600,
            "po południu": 15 * 3600,
            "wieczorem": 19 * 3600,
            "w nocy": 22 * 3600,
        ],
        recurrenceKeywords: [
            "co poniedziałek": "FREQ=WEEKLY;BYDAY=MO",
            "co wtorek": "FREQ=WEEKLY;BYDAY=TU",
            "co środę": "FREQ=WEEKLY;BYDAY=WE",
            "co środa": "FREQ=WEEKLY;BYDAY=WE",
            "co czwartek": "FREQ=WEEKLY;BYDAY=TH",
            "co piątek": "FREQ=WEEKLY;BYDAY=FR",
            "co sobotę": "FREQ=WEEKLY;BYDAY=SA",
            "co sobota": "FREQ=WEEKLY;BYDAY=SA",
            "co niedzielę": "FREQ=WEEKLY;BYDAY=SU",
            "co niedziela": "FREQ=WEEKLY;BYDAY=SU",
        ],
        recurrenceFrequency: [
            "co dzień": "FREQ=DAILY",
            "codziennie": "FREQ=DAILY",
            "co tydzień": "FREQ=WEEKLY",
            "co tygodnie": "FREQ=WEEKLY",
            "co miesiąc": "FREQ=MONTHLY",
            "co miesięcznie": "FREQ=MONTHLY",
        ],
        relativeUnits: [
            "dzień": 1, "dni": 1, "dnia": 1,
            "tydzień": 7, "tygodnie": 7, "tygodni": 7,
            "miesiąc": 30, "miesiące": 30, "miesięcy": 30,
        ]
    )
}
