import Foundation

/// Normalizes a speaker label to a canonical key. Circleback imports store the
/// participant `speakerID` with spaces replaced by underscores while transcript
/// segments keep the raw spelling; without normalization a rename appends a
/// duplicate participant instead of updating the existing one.
public func canonicalSpeakerKey(_ raw: String) -> String {
    raw
        .replacingOccurrences(of: "_", with: " ")
        .folding(options: .diacriticInsensitive, locale: nil)
        .lowercased()
        .split(separator: " ")
        .joined(separator: " ")
}

/// Updates the participant whose canonical key matches `rawSpeaker` in place,
/// appending a new participant only when none matches. Guarantees no two
/// participants share a canonical key.
///
/// When an existing participant is found, its `speakerID` is **realigned to
/// `rawSpeaker`** (the segment's own spelling). This keeps `MergeStage.displayNameMap`
/// and `TranscriptViewModel.displayName(for:)` — both exact-match on `speakerID` —
/// in sync with the segment's `speaker` field, so the renamed label is actually
/// visible in the transcript after the update.
public func renameSpeaker(
    in participants: [MeetingParticipant],
    rawSpeaker: String,
    to displayName: String,
    personID: UUID?
) -> [MeetingParticipant] {
    let key = canonicalSpeakerKey(rawSpeaker)
    // Find the first participant whose canonical key matches, then drop ALL
    // participants sharing that key (prevents two entries after back-compat
    // imports that stored both forms).
    var result: [MeetingParticipant] = []
    var matched = false
    for participant in participants {
        if canonicalSpeakerKey(participant.speakerID) == key {
            if !matched {
                // Realign speakerID to the raw speaker token so exact-match
                // lookups hit the segment's own form.
                result.append(
                    MeetingParticipant(speakerID: rawSpeaker, displayName: displayName, personID: personID)
                )
                matched = true
            }
            // Subsequent duplicates with the same canonical key are dropped.
        } else {
            result.append(participant)
        }
    }
    if !matched {
        result.append(
            MeetingParticipant(speakerID: rawSpeaker, displayName: displayName, personID: personID)
        )
    }
    return result
}
