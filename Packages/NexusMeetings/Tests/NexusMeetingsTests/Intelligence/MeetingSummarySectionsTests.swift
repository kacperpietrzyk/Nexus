import Foundation
import Testing

@testable import NexusMeetings

// MARK: - parse: empty inputs

@Test func parseNilSummaryReturnsEmptySections() {
    let sections = MeetingSummarySections.parse(summaryText: nil)
    #expect(sections == .empty)
    #expect(sections.overview == nil)
    #expect(sections.decisions.isEmpty)
    #expect(sections.extraSections.isEmpty)
}

@Test func parseWhitespaceOnlySummaryReturnsEmptySections() {
    #expect(MeetingSummarySections.parse(summaryText: "") == .empty)
    #expect(MeetingSummarySections.parse(summaryText: "  \n\t\n  ") == .empty)
}

// MARK: - parse: native pipeline shape (MeetingPromptBuilder default prompt)

@Test func parseNativePipelineShape() {
    let summary = """
        ## TL;DR
        The team agreed to ship v2 on Friday. QA starts Wednesday.

        ## Key topics
        - Release timeline
        - Test coverage gaps

        ## Decisions made
        - Ship v2 on Friday
        - Drop the legacy importer
        """
    let sections = MeetingSummarySections.parse(summaryText: summary)
    #expect(sections.overview == "The team agreed to ship v2 on Friday. QA starts Wednesday.")
    #expect(sections.decisions == ["Ship v2 on Friday", "Drop the legacy importer"])
    #expect(
        sections.extraSections == [
            MeetingSummarySections.Section(title: "Key topics", items: ["Release timeline", "Test coverage gaps"])
        ])
}

// MARK: - parse: Circleback import shape (#### headings, * bullets, Polish)

@Test func parseCirclebackImportShape() {
    let summary = """
        #### Przegląd
        * Spotkanie poświęcone prezentacji VendorA — omówiono architekturę
        * Klient miał poprzedni POC ok. **1,5 roku** temu

        #### Następne kroki i zakres POC
        * Klient zredaguje listę pytań
        """
    let sections = MeetingSummarySections.parse(summaryText: summary)
    #expect(
        sections.overview
            == "Spotkanie poświęcone prezentacji VendorA — omówiono architekturę\nKlient miał poprzedni POC ok. **1,5 roku** temu"
    )
    #expect(sections.decisions.isEmpty)
    #expect(
        sections.extraSections == [
            MeetingSummarySections.Section(title: "Następne kroki i zakres POC", items: ["Klient zredaguje listę pytań"])
        ])
}

// MARK: - parse: heading variations

@Test func parseToleratesHeadingLevelsCaseAndTrailingHashes() {
    let summary = """
        # summary
        Quick sync about hiring.

        ### DECISIONS ##
        - Open two roles
        """
    let sections = MeetingSummarySections.parse(summaryText: summary)
    #expect(sections.overview == "Quick sync about hiring.")
    #expect(sections.decisions == ["Open two roles"])
    #expect(sections.extraSections.isEmpty)
}

@Test func parseMatchesPolishDecisionHeadings() {
    let decyzje = MeetingSummarySections.parse(summaryText: "## Decyzje\n- Zrobimy POC w marcu")
    #expect(decyzje.decisions == ["Zrobimy POC w marcu"])

    let ustalenia = MeetingSummarySections.parse(summaryText: "## Ustalenia\n- Budżet zatwierdzony")
    #expect(ustalenia.decisions == ["Budżet zatwierdzony"])
}

@Test func parseMatchesOverviewKeywordsIncludingPolish() {
    #expect(MeetingSummarySections.parse(summaryText: "## Overview\nShort recap.").overview == "Short recap.")
    #expect(MeetingSummarySections.parse(summaryText: "#### Podsumowanie\nKrótka notatka.").overview == "Krótka notatka.")
}

// MARK: - parse: bullet variants

@Test func parseStripsAllBulletVariantsInDecisions() {
    let summary = """
        ## Decisions made
        - Dash decision
        * Star decision
        • Dot decision
        1. First numbered
        2) Second numbered
        Plain line decision
        """
    let sections = MeetingSummarySections.parse(summaryText: summary)
    #expect(
        sections.decisions == [
            "Dash decision",
            "Star decision",
            "Dot decision",
            "First numbered",
            "Second numbered",
            "Plain line decision",
        ])
}

// MARK: - parse: fallbacks

@Test func parsePlainTextWithoutHeadingsBecomesOverview() {
    let summary = "We discussed the roadmap and agreed on priorities.\nNothing else was decided."
    let sections = MeetingSummarySections.parse(summaryText: summary)
    #expect(sections.overview == "We discussed the roadmap and agreed on priorities.\nNothing else was decided.")
    #expect(sections.decisions.isEmpty)
    #expect(sections.extraSections.isEmpty)
}

@Test func parseUsesPreambleAsOverviewWhenNoOverviewHeadingExists() {
    let summary = """
        Intro paragraph before any heading.

        ## Risks
        - Vendor lock-in
        """
    let sections = MeetingSummarySections.parse(summaryText: summary)
    #expect(sections.overview == "Intro paragraph before any heading.")
    #expect(sections.extraSections == [MeetingSummarySections.Section(title: "Risks", items: ["Vendor lock-in"])])
}

@Test func parseOverviewSectionWinsOverPreamble() {
    let summary = """
        Stray preamble.

        ## TL;DR
        Real overview.
        """
    #expect(MeetingSummarySections.parse(summaryText: summary).overview == "Real overview.")
}

@Test func parseEmptyDecisionsSectionYieldsNoDecisions() {
    let summary = """
        ## TL;DR
        Recap.

        ## Decisions made
        """
    let sections = MeetingSummarySections.parse(summaryText: summary)
    #expect(sections.overview == "Recap.")
    #expect(sections.decisions.isEmpty)
    #expect(sections.extraSections.isEmpty)
}

@Test func parseDropsExtraSectionsWithoutItems() {
    let summary = """
        ## TL;DR
        Recap.

        ## Key topics

        ## Risks
        - One risk
        """
    let sections = MeetingSummarySections.parse(summaryText: summary)
    #expect(sections.extraSections == [MeetingSummarySections.Section(title: "Risks", items: ["One risk"])])
}

@Test func parseConcatenatesMultipleDecisionSections() {
    let summary = """
        ## Decisions made
        - First

        ## Decyzje
        - Druga
        """
    #expect(MeetingSummarySections.parse(summaryText: summary).decisions == ["First", "Druga"])
}

// MARK: - insights: empty inputs

@Test func insightsEmptyInputsProduceEmptyInsights() {
    let insights = MeetingInsights.insights(durationSec: nil, segments: [], transcriptText: nil)
    #expect(insights == .empty)
    #expect(insights.durationText == nil)
    #expect(insights.speakerShares.isEmpty)
    #expect(insights.wordCount == 0)
    #expect(insights.topTerms.isEmpty)
}

@Test func insightsZeroDurationHasNoDurationText() {
    #expect(MeetingInsights.insights(durationSec: 0, segments: [], transcriptText: nil).durationText == nil)
}

// MARK: - insights: duration formatting

@Test func insightsFormatsDuration() {
    func text(_ seconds: Int) -> String? {
        MeetingInsights.insights(durationSec: seconds, segments: [], transcriptText: nil).durationText
    }
    #expect(text(45) == "45s")
    #expect(text(300) == "5m")
    #expect(text(5400) == "1h 30m")
    #expect(text(7200) == "2h")
}

// MARK: - insights: speaker shares

@Test func insightsSingleSpeakerGetsFullShare() {
    let segments = [
        MeetingSpeakerSegment(startMs: 0, endMs: 30_000, speaker: "Me", text: "Hello"),
        MeetingSpeakerSegment(startMs: 30_000, endMs: 60_000, speaker: "Me", text: "Again"),
    ]
    let insights = MeetingInsights.insights(durationSec: 60, segments: segments, transcriptText: nil)
    #expect(insights.speakerShares == [MeetingInsights.SpeakerShare(speaker: "Me", talkMs: 60_000, share: 1.0)])
}

@Test func insightsManySpeakersSortedByTalkTimeDescending() {
    let segments = [
        MeetingSpeakerSegment(startMs: 0, endMs: 10_000, speaker: "Anna", text: "a"),
        MeetingSpeakerSegment(startMs: 10_000, endMs: 40_000, speaker: "Bart", text: "b"),
        MeetingSpeakerSegment(startMs: 40_000, endMs: 50_000, speaker: "Anna", text: "c"),
    ]
    let shares = MeetingInsights.insights(durationSec: 50, segments: segments, transcriptText: nil).speakerShares
    #expect(shares.map(\.speaker) == ["Bart", "Anna"])
    #expect(shares.map(\.talkMs) == [30_000, 20_000])
    #expect(shares[0].share == 0.6)
    #expect(shares[1].share == 0.4)
}

@Test func insightsSpeakerTieBreaksAlphabetically() {
    let segments = [
        MeetingSpeakerSegment(startMs: 0, endMs: 10_000, speaker: "Zoe", text: "z"),
        MeetingSpeakerSegment(startMs: 10_000, endMs: 20_000, speaker: "Adam", text: "a"),
    ]
    let shares = MeetingInsights.insights(durationSec: 20, segments: segments, transcriptText: nil).speakerShares
    #expect(shares.map(\.speaker) == ["Adam", "Zoe"])
}

@Test func insightsIgnoresNonPositiveSegmentDurations() {
    let segments = [
        MeetingSpeakerSegment(startMs: 10_000, endMs: 10_000, speaker: "Me", text: "zero"),
        MeetingSpeakerSegment(startMs: 20_000, endMs: 5_000, speaker: "Me", text: "negative"),
    ]
    #expect(MeetingInsights.insights(durationSec: 20, segments: segments, transcriptText: nil).speakerShares.isEmpty)
}

// MARK: - insights: word count + top terms

@Test func insightsCountsTranscriptWords() {
    let insights = MeetingInsights.insights(durationSec: nil, segments: [], transcriptText: "one two  three\nfour")
    #expect(insights.wordCount == 4)
}

@Test func insightsTopTermsFilterStopwordsAndShortWords() {
    let transcript = "The budget and the budget for the budget meeting meeting i w na to of an"
    let insights = MeetingInsights.insights(durationSec: nil, segments: [], transcriptText: transcript)
    #expect(insights.topTerms == ["budget", "meeting"])
}

@Test func insightsTopTermsFilterPolishStopwordsAndKeepDiacritics() {
    let transcript = "Spotkanie się nie jest ale wdrożenie wdrożenie spotkanie spotkanie oraz tylko"
    let insights = MeetingInsights.insights(durationSec: nil, segments: [], transcriptText: transcript)
    #expect(insights.topTerms == ["spotkanie", "wdrożenie"])
}

@Test func insightsTopTermsTieOrderIsAlphabetical() {
    let transcript = "zebra zebra apple apple mango mango"
    let insights = MeetingInsights.insights(durationSec: nil, segments: [], transcriptText: transcript)
    #expect(insights.topTerms == ["apple", "mango", "zebra"])
}

@Test func insightsTopTermsMergeDiacriticVariants() {
    let transcript = "wdrożenie wdrozenie wdrożenie budżet"
    let insights = MeetingInsights.insights(durationSec: nil, segments: [], transcriptText: transcript)
    // Folded forms merge into one count; the first-seen original spelling is displayed.
    #expect(insights.topTerms == ["wdrożenie", "budżet"])
}

@Test func insightsTopTermsCapAtFive() {
    // all words ≥ minTermLength (3), none in stopwords
    let transcript = "alpha bravo charlie delta echo foxtrot golf"
    let insights = MeetingInsights.insights(durationSec: nil, segments: [], transcriptText: transcript)
    #expect(insights.topTerms.count == 5)
    #expect(insights.topTerms == ["alpha", "bravo", "charlie", "delta", "echo"])
}

// MARK: - insights: speaker-label stripping + Polish fillers

@Test func topTermsExcludeSpeakerLabelsAndPolishFillers() {
    let transcript = """
        Participant 1: żeby zrobić wdrożenie systemu, może po prostu wiem
        Participant 2: wdrożenie systemu to wdrożenie, prostu wiem
        """
    let insights = MeetingInsights.insights(durationSec: 600, segments: [], transcriptText: transcript)
    // Speaker label must not be a topic.
    #expect(insights.topTerms.contains("participant") == false)
    // Polish fillers must be filtered (diacritic-folded match).
    for filler in ["zeby", "moze", "prostu", "wiem"] {
        #expect(insights.topTerms.contains { $0.folding(options: .diacriticInsensitive, locale: nil) == filler } == false)
    }
    // The real repeated topic survives.
    #expect(insights.topTerms.contains { $0.folding(options: .diacriticInsensitive, locale: nil) == "wdrozenie" })
}

// MARK: - insights: top terms from segments (Circleback import format)

/// Circleback `transcriptText` shape: `"[00:00:00] Participant 1\n<text>\n"`.
/// The speaker-header line must NOT leak into topics; `bylo` (real ł, not ASCII)
/// must be blocked by the stopword fold; `takiego/trzeba/dobra` idem.
@Test func topTermsUsesSegmentTextNotTranscriptHeaders() {
    let transcriptText = """
        [00:00:00] Participant 1
        wdrożenie systemu było takiego trzeba dobra wdrożenie wdrożenie
        [00:00:30] Participant 2
        wdrożenie systemu to wdrożenie dobra trzeba
        """
    let segments = [
        MeetingSpeakerSegment(
            startMs: 0, endMs: 30_000, speaker: "Participant 1",
            text: "wdrożenie systemu było takiego trzeba dobra wdrożenie wdrożenie"
        ),
        MeetingSpeakerSegment(
            startMs: 30_000, endMs: 60_000, speaker: "Participant 2",
            text: "wdrożenie systemu to wdrożenie dobra trzeba"
        ),
    ]
    let insights = MeetingInsights.insights(
        durationSec: 60, segments: segments, transcriptText: transcriptText
    )
    // Speaker-header words must not appear.
    #expect(insights.topTerms.contains("participant") == false)
    // Polish fillers (real ł spelling for było) must be blocked.
    let foldedTerms = insights.topTerms.map {
        $0.lowercased().replacingOccurrences(of: "ł", with: "l")
            .folding(options: .diacriticInsensitive, locale: nil)
    }
    #expect(foldedTerms.contains("bylo") == false)
    #expect(foldedTerms.contains("takiego") == false)
    #expect(foldedTerms.contains("trzeba") == false)
    #expect(foldedTerms.contains("dobra") == false)
    // Real domain term survives.
    #expect(insights.topTerms.contains { $0.folding(options: .diacriticInsensitive, locale: nil) == "wdrozenie" })
    // Word count still reflects the full transcriptText (not just segment text).
    #expect(insights.wordCount > 0)
}

// MARK: - insights: speaker-name mapping

@Test func speakerSharesUseAssignedDisplayNames() {
    let segments = [
        MeetingSpeakerSegment(startMs: 0, endMs: 6_000, speaker: "Participant 1", text: "a"),
        MeetingSpeakerSegment(startMs: 6_000, endMs: 10_000, speaker: "Participant 2", text: "b"),
    ]
    let names = ["participant 1": "Janek", "participant 2": "Kacper"]
    let insights = MeetingInsights.insights(
        durationSec: 10,
        segments: segments,
        transcriptText: "x",
        speakerNames: names
    )
    // "Participant 1" talks 6s (60%), so it should appear first after rename.
    #expect(insights.speakerShares.first?.speaker == "Janek")
    #expect(insights.speakerShares.contains { $0.speaker == "Participant 1" } == false)
}

@Test func speakerSharesMergeSameDisplayName() {
    let segments = [
        MeetingSpeakerSegment(startMs: 0, endMs: 4_000, speaker: "participant_1", text: "a"),
        MeetingSpeakerSegment(startMs: 4_000, endMs: 10_000, speaker: "Participant 1", text: "b"),
    ]
    // Both raw keys canonicalize to "participant 1" → same display name.
    let names = ["participant 1": "Janek"]
    let insights = MeetingInsights.insights(
        durationSec: 10, segments: segments, transcriptText: "x", speakerNames: names
    )
    #expect(insights.speakerShares.count == 1)
    #expect(insights.speakerShares[0].speaker == "Janek")
    #expect(insights.speakerShares[0].talkMs == 10_000)  // 4000 + 6000 summed, not last-wins
}
