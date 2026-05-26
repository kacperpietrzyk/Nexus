import Foundation

enum PencilRecognitionLanguages {
    private static let defaultRegions: [String: String] = [
        "ar": "SA",
        "ars": "SA",
        "cs": "CZ",
        "da": "DK",
        "de": "DE",
        "en": "US",
        "es": "ES",
        "fr": "FR",
        "id": "ID",
        "it": "IT",
        "ja": "JP",
        "ko": "KR",
        "ms": "MY",
        "nl": "NL",
        "pl": "PL",
        "pt": "BR",
        "ro": "RO",
        "ru": "RU",
        "sv": "SE",
        "th": "TH",
        "tr": "TR",
        "uk": "UA",
        "vi": "VT",
    ]

    static func make(for locale: Locale = .current) -> [String] {
        let language = locale.language
        guard let code = language.languageCode?.identifier else {
            return ["en-US"]
        }

        let region = language.region?.identifier ?? defaultRegions[code]
        let primary = region.map { "\(code)-\($0)" } ?? code
        return primary == "en-US" ? ["en-US"] : [primary, "en-US"]
    }
}
