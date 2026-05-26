import Foundation
import Testing

@testable import NexusMeetings

@Test func stubProviderRoundtrip() async throws {
    let provider = StubMeetingTranscriptionProvider(
        result: .init(
            text: "Cześć",
            segments: [
                .init(startMs: 0, endMs: 500, text: "Cześć")
            ],
            detectedLanguage: "pl"
        )
    )

    let result = try await provider.transcribe(
        audioURL: URL(fileURLWithPath: "/tmp/x.wav"),
        languageHint: nil,
        progress: { _ in }
    )

    #expect(result.text == "Cześć")
    #expect(result.detectedLanguage == "pl")
    #expect(result.segments.count == 1)
}

private struct StubMeetingTranscriptionProvider: MeetingTranscriptionProvider {
    let result: TranscriptionResult
    var identifier: String { "stub" }

    func transcribe(
        audioURL: URL,
        languageHint: String?,
        progress: @MainActor @Sendable (Double) -> Void
    ) async throws -> TranscriptionResult {
        result
    }
}

@Test func languageHintNormalizationAcceptsNilBaseLocaleAndCaseVariants() {
    #expect(TranscriptionLanguageHint.normalize(nil) == nil)
    #expect(TranscriptionLanguageHint.normalize("pl") == "pl")
    #expect(TranscriptionLanguageHint.normalize("pl-PL") == "pl")
    #expect(TranscriptionLanguageHint.normalize("en_US") == "en")
    #expect(TranscriptionLanguageHint.normalize("PL-pl") == "pl")
    #expect(TranscriptionLanguageHint.normalize("  Fr-ca  ") == "fr")
    #expect(TranscriptionLanguageHint.normalize("xx-YY") == nil)
    #expect(TranscriptionLanguageHint.normalize("polish") == nil)
}

@Test func whisperKitDecodingOptionsUseOnlyNormalizedLanguageHints() {
    #expect(WhisperKitMeetingProviderMapping.normalizedDecodingLanguage(from: "pl-PL") == "pl")
    #expect(WhisperKitMeetingProviderMapping.normalizedDecodingLanguage(from: "EN_us") == "en")
    #expect(WhisperKitMeetingProviderMapping.normalizedDecodingLanguage(from: "xx-YY") == nil)
    #expect(WhisperKitMeetingProviderMapping.normalizedDecodingLanguage(from: nil) == nil)
}

@Test func parakeetMappingCoalescesSentencePieceTokensIntoWords() {
    let result = ParakeetTDTProviderMapping.map(
        text: "Cześć świat",
        duration: 1.0,
        tokenTimings: [
            .init(startSeconds: 0.00, endSeconds: 0.10, text: "▁Cze"),
            .init(startSeconds: 0.10, endSeconds: 0.24, text: "ść"),
            .init(startSeconds: 0.32, endSeconds: 0.45, text: "▁świ"),
            .init(startSeconds: 0.45, endSeconds: 0.60, text: "at"),
        ],
        detectedLanguage: "pl"
    )

    #expect(result.text == "Cześć świat")
    #expect(result.detectedLanguage == "pl")
    #expect(result.segments.count == 1)
    #expect(result.segments.first?.startMs == 0)
    #expect(result.segments.first?.endMs == 600)
    #expect(
        result.segments.first?.words == [
            TranscriptionWord(startMs: 0, endMs: 240, text: "Cześć"),
            TranscriptionWord(startMs: 320, endMs: 600, text: "świat"),
        ])
}

@Test func parakeetMappingDropsInvalidTimingsAndFallsBackOnlyForPositiveDuration() {
    let timed = ParakeetTDTProviderMapping.map(
        text: "valid",
        duration: 0,
        tokenTimings: [
            .init(startSeconds: -0.25, endSeconds: 0.10, text: "▁valid"),
            .init(startSeconds: 0.20, endSeconds: 0.20, text: "▁zero"),
            .init(startSeconds: 0.40, endSeconds: 0.30, text: "▁reversed"),
        ],
        detectedLanguage: "en"
    )
    let noPositiveDuration = ParakeetTDTProviderMapping.map(
        text: "text only",
        duration: 0,
        tokenTimings: [],
        detectedLanguage: "und"
    )
    let positiveDuration = ParakeetTDTProviderMapping.map(
        text: "text only",
        duration: 1.25,
        tokenTimings: [],
        detectedLanguage: "und"
    )

    #expect(
        timed.segments.first?.words == [
            TranscriptionWord(startMs: 0, endMs: 100, text: "valid")
        ])
    #expect(noPositiveDuration.segments.isEmpty)
    #expect(
        positiveDuration.segments == [
            TranscriptionSegment(startMs: 0, endMs: 1_250, text: "text only")
        ])
}

@Test func timingMapperDropsNonFiniteWordAndSegmentTimings() {
    let invalidValues: [Double] = [
        .nan,
        .infinity,
        -.infinity,
    ]

    for value in invalidValues {
        #expect(
            TranscriptionTimingMapper.word(
                from: RawTranscriptionTiming(startSeconds: value, endSeconds: 1.0, text: "word")
            ) == nil
        )
        #expect(
            TranscriptionTimingMapper.word(
                from: RawTranscriptionTiming(startSeconds: 0.0, endSeconds: value, text: "word")
            ) == nil
        )
        #expect(
            TranscriptionTimingMapper.segment(
                startSeconds: value,
                endSeconds: 1.0,
                text: "segment"
            ) == nil
        )
        #expect(
            TranscriptionTimingMapper.segment(
                startSeconds: 0.0,
                endSeconds: value,
                text: "segment"
            ) == nil
        )
    }
}

@Test func timingMapperDropsOutOfRangeFiniteTimings() {
    let outOfRangePositiveValues = [
        Double.greatestFiniteMagnitude,
        Double(Int.max) / 1_000 + 1,
    ]

    for value in outOfRangePositiveValues {
        #expect(
            TranscriptionTimingMapper.word(
                from: RawTranscriptionTiming(startSeconds: value, endSeconds: 1.0, text: "word")
            ) == nil
        )
        #expect(
            TranscriptionTimingMapper.word(
                from: RawTranscriptionTiming(startSeconds: 0.0, endSeconds: value, text: "word")
            ) == nil
        )
        #expect(
            TranscriptionTimingMapper.segment(
                startSeconds: value,
                endSeconds: 1.0,
                text: "segment"
            ) == nil
        )
        #expect(
            TranscriptionTimingMapper.segment(
                startSeconds: 0.0,
                endSeconds: value,
                text: "segment"
            ) == nil
        )
    }

    let outOfRangeNegativeEnd = Double(Int.min) / 1_000 - 1
    #expect(
        TranscriptionTimingMapper.word(
            from: RawTranscriptionTiming(startSeconds: 0.0, endSeconds: outOfRangeNegativeEnd, text: "word")
        ) == nil
    )
    #expect(
        TranscriptionTimingMapper.segment(
            startSeconds: 0.0,
            endSeconds: outOfRangeNegativeEnd,
            text: "segment"
        ) == nil
    )
}

@Test func parakeetInvalidBoundaryTokenDoesNotMergeNextContinuationIntoPreviousWord() {
    let words = ParakeetTDTProviderMapping.coalescedWords(
        from: [
            .init(startSeconds: 0.0, endSeconds: 0.2, text: "▁Cześć"),
            .init(startSeconds: 0.3, endSeconds: 0.2, text: "▁bad"),
            .init(startSeconds: 0.4, endSeconds: 0.6, text: "tail"),
        ]
    )

    #expect(
        words == [
            TranscriptionWord(startMs: 0, endMs: 200, text: "Cześć"),
            TranscriptionWord(startMs: 400, endMs: 600, text: "tail"),
        ])
}

@Test func parakeetNonFiniteBoundaryTokenDoesNotMergeNextContinuationIntoPreviousWord() {
    let words = ParakeetTDTProviderMapping.coalescedWords(
        from: [
            .init(startSeconds: 0.0, endSeconds: 0.2, text: "▁Cześć"),
            .init(startSeconds: .nan, endSeconds: 0.4, text: "▁bad"),
            .init(startSeconds: 0.5, endSeconds: 0.7, text: "tail"),
        ]
    )

    #expect(
        words == [
            TranscriptionWord(startMs: 0, endMs: 200, text: "Cześć"),
            TranscriptionWord(startMs: 500, endMs: 700, text: "tail"),
        ])
}

@Test func whisperKitMappingClampsAndFiltersInvalidWordsAndSegments() {
    let result = WhisperKitMeetingProviderMapping.map(
        [
            WhisperKitMeetingRawResult(
                text: " Cześć ",
                segments: [
                    WhisperKitMeetingRawSegment(
                        start: -0.10,
                        end: 0.30,
                        text: " Cześć ",
                        words: [
                            WhisperKitMeetingRawWord(start: -0.10, end: 0.10, text: " Cześć "),
                            WhisperKitMeetingRawWord(start: 0.20, end: 0.20, text: "zero"),
                            WhisperKitMeetingRawWord(start: 0.40, end: 0.30, text: "reversed"),
                        ]
                    ),
                    WhisperKitMeetingRawSegment(
                        start: 0.40,
                        end: 0.40,
                        text: "drop",
                        words: []
                    ),
                ],
                language: "PL-pl"
            )
        ],
        languageHint: nil
    )

    #expect(result.text == "Cześć")
    #expect(result.detectedLanguage == "pl")
    #expect(
        result.segments == [
            TranscriptionSegment(
                startMs: 0,
                endMs: 300,
                text: "Cześć",
                words: [
                    TranscriptionWord(startMs: 0, endMs: 100, text: "Cześć")
                ]
            )
        ])
}

@Test func whisperKitMappingDoesNotCreateZeroLengthTextOnlyFallback() {
    let result = WhisperKitMeetingProviderMapping.map(
        [
            WhisperKitMeetingRawResult(
                text: "text only",
                segments: [],
                language: "unsupported"
            )
        ],
        languageHint: nil
    )

    #expect(result.text == "text only")
    #expect(result.detectedLanguage == "und")
    #expect(result.segments.isEmpty)
}
