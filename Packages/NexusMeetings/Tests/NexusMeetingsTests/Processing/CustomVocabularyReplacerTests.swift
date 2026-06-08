import Foundation
import Testing

@testable import NexusMeetings

struct CustomVocabularyReplacerTests {
    @Test func emptyVocabularyIsIdentity() {
        let replacer = CustomVocabularyReplacer([])
        #expect(replacer.isEmpty)
        #expect(replacer.apply(to: "threat forge shipped today") == "threat forge shipped today")
    }

    @Test func allBlankEntriesAreIdentity() {
        let replacer = CustomVocabularyReplacer([
            CustomVocabularyEntry(term: "   ", replacement: "X"),
            CustomVocabularyEntry(term: "", replacement: "Y"),
        ])
        #expect(replacer.isEmpty)
        #expect(replacer.apply(to: "nothing changes") == "nothing changes")
    }

    @Test func caseInsensitiveMatchEmitsCanonicalReplacement() {
        let replacer = CustomVocabularyReplacer([
            CustomVocabularyEntry(term: "threat forge", replacement: "ThreatForge")
        ])
        // Match is case-insensitive on the term; the canonical spelling is emitted
        // regardless of how the term was cased in the transcript.
        #expect(replacer.apply(to: "We shipped Threat Forge.") == "We shipped ThreatForge.")
        #expect(replacer.apply(to: "we shipped threat forge today") == "we shipped ThreatForge today")
        #expect(replacer.apply(to: "THREAT FORGE rocks") == "ThreatForge rocks")
    }

    @Test func longestTermWinsOverShorterSubterm() {
        let replacer = CustomVocabularyReplacer([
            CustomVocabularyEntry(term: "forge", replacement: "Forge"),
            CustomVocabularyEntry(term: "threat forge", replacement: "ThreatForge"),
        ])
        // "threat forge" must resolve as a unit, not "threat Forge".
        #expect(replacer.apply(to: "threat forge") == "ThreatForge")
        // A standalone "forge" still gets its own replacement.
        #expect(replacer.apply(to: "the forge is hot") == "the Forge is hot")
    }

    @Test func wordBoundaryPreventsSubstringRewrite() {
        let replacer = CustomVocabularyReplacer([
            CustomVocabularyEntry(term: "forge", replacement: "Forge")
        ])
        // Inside a larger word -> untouched.
        #expect(replacer.apply(to: "they forged ahead") == "they forged ahead")
        #expect(replacer.apply(to: "reinforge it") == "reinforge it")
        // Punctuation is a boundary -> matched.
        #expect(replacer.apply(to: "the forge, hot") == "the Forge, hot")
    }

    @Test func deterministicAcrossRepeatedApplications() {
        let entries = [
            CustomVocabularyEntry(term: "kube", replacement: "Kube"),
            CustomVocabularyEntry(term: "kube cluster", replacement: "KubeCluster"),
        ]
        let replacer = CustomVocabularyReplacer(entries)
        let input = "the kube cluster and the kube node"
        let once = replacer.apply(to: input)
        #expect(once == "the KubeCluster and the Kube node")
        // Idempotent / order-stable on a second run over the same input.
        #expect(replacer.apply(to: input) == once)
    }

    @Test func laterShorterRuleDoesNotRematchAnEarlierRulesOutput() {
        // ME2: "new york" -> "New York" then "york" -> "York City" must NOT cascade
        // into "New York City" — the first rule's output is protected from being
        // re-matched by the later, shorter rule.
        let replacer = CustomVocabularyReplacer([
            CustomVocabularyEntry(term: "new york", replacement: "New York"),
            CustomVocabularyEntry(term: "york", replacement: "York City"),
        ])
        #expect(replacer.apply(to: "new york office") == "New York office")
        // A standalone "york" (not produced by an earlier rule) still gets replaced.
        #expect(replacer.apply(to: "old york town") == "old York City town")
    }

    @Test func appliesToSegmentTextOnlyLeavingTimingsAndSpeaker() {
        let replacer = CustomVocabularyReplacer([
            CustomVocabularyEntry(term: "threat forge", replacement: "ThreatForge")
        ])
        let segments = [
            MeetingSpeakerSegment(startMs: 0, endMs: 1000, speaker: "Speaker_1", text: "threat forge update"),
            MeetingSpeakerSegment(startMs: 1000, endMs: 2000, speaker: "Me", text: "no change here"),
        ]
        let corrected = replacer.apply(to: segments)
        #expect(corrected[0].text == "ThreatForge update")
        #expect(corrected[0].speaker == "Speaker_1")
        #expect(corrected[0].startMs == 0)
        #expect(corrected[1].text == "no change here")
    }

    @Test func emptyVocabularyLeavesSegmentsUnchanged() {
        let replacer = CustomVocabularyReplacer([])
        let segments = [
            MeetingSpeakerSegment(startMs: 0, endMs: 1000, speaker: "Speaker_1", text: "verbatim")
        ]
        #expect(replacer.apply(to: segments) == segments)
    }

    @Test func diacriticInsensitiveMatch() {
        let replacer = CustomVocabularyReplacer([
            CustomVocabularyEntry(term: "Łódź", replacement: "Lodz HQ")
        ])
        #expect(replacer.apply(to: "meeting in lodz tomorrow") == "meeting in lodz tomorrow")
        #expect(replacer.apply(to: "meeting in Łódź tomorrow") == "meeting in Lodz HQ tomorrow")
    }
}
