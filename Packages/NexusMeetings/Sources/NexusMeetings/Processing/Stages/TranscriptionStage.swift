import Foundation

public struct TranscriptionStageOutput: Sendable {
    public let me: TranscriptionResult
    public let others: TranscriptionResult
    public let providerProfile: String
    public let detectedLanguage: String

    public init(
        me: TranscriptionResult,
        others: TranscriptionResult,
        providerProfile: String,
        detectedLanguage: String
    ) {
        self.me = me
        self.others = others
        self.providerProfile = providerProfile
        self.detectedLanguage = detectedLanguage
    }
}

public final class TranscriptionStage: Sendable {
    private let primary: any MeetingTranscriptionProvider
    private let fallback: any MeetingTranscriptionProvider
    private let minTextLength: Int

    public init(
        primary: any MeetingTranscriptionProvider,
        fallback: any MeetingTranscriptionProvider,
        minTextLength: Int = 1
    ) {
        self.primary = primary
        self.fallback = fallback
        self.minTextLength = minTextLength
    }

    public func run(
        meURL: URL,
        othersURL: URL,
        languageHint: String?
    ) async throws -> TranscriptionStageOutput {
        let progress: @MainActor @Sendable (Double) -> Void = { _ in }

        async let mePrimary = primary.transcribe(
            audioURL: meURL,
            languageHint: languageHint,
            progress: progress
        )
        async let othersPrimary = primary.transcribe(
            audioURL: othersURL,
            languageHint: languageHint,
            progress: progress
        )
        let (meResult, othersResult) = try await (mePrimary, othersPrimary)

        if isEmpty(meResult) && isEmpty(othersResult) {
            async let meFallback = fallback.transcribe(
                audioURL: meURL,
                languageHint: languageHint,
                progress: progress
            )
            async let othersFallback = fallback.transcribe(
                audioURL: othersURL,
                languageHint: languageHint,
                progress: progress
            )
            let (meFallbackResult, othersFallbackResult) = try await (meFallback, othersFallback)

            return TranscriptionStageOutput(
                me: meFallbackResult,
                others: othersFallbackResult,
                providerProfile: fallback.identifier,
                detectedLanguage: detectedLanguage(
                    meResult: meFallbackResult,
                    othersResult: othersFallbackResult,
                    languageHint: languageHint
                )
            )
        }

        return TranscriptionStageOutput(
            me: meResult,
            others: othersResult,
            providerProfile: primary.identifier,
            detectedLanguage: detectedLanguage(
                meResult: meResult,
                othersResult: othersResult,
                languageHint: languageHint
            )
        )
    }

    private func isEmpty(_ result: TranscriptionResult) -> Bool {
        result.text.trimmingCharacters(in: .whitespacesAndNewlines).count < minTextLength
    }

    private func detectedLanguage(
        meResult: TranscriptionResult,
        othersResult: TranscriptionResult,
        languageHint: String?
    ) -> String {
        if hasText(meResult), isDetected(meResult.detectedLanguage) {
            return meResult.detectedLanguage
        }

        if hasText(othersResult), isDetected(othersResult.detectedLanguage) {
            return othersResult.detectedLanguage
        }

        return TranscriptionLanguageHint.normalize(languageHint) ?? "und"
    }

    private func hasText(_ result: TranscriptionResult) -> Bool {
        !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isDetected(_ language: String) -> Bool {
        !language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && language != "und"
    }
}
