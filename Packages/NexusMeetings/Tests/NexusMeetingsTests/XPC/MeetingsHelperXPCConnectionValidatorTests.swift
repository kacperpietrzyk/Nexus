import Foundation
import Testing

@testable import NexusMeetings

@Test func xpcValidatorAcceptsSignedNexusMacHost() {
    let validator = MeetingsHelperXPCConnectionValidator()
    let verdict = validator.validate(
        signingInfo: MeetingsHelperXPCSigningInfo(
            teamIdentifier: "UDZLCK86PY",
            bundleIdentifier: "com.kacperpietrzyk.Nexus.Mac"
        )
    )

    #expect(verdict == .accepted)
}

@Test func xpcValidatorAcceptsSignedMeetingsHelper() {
    let validator = MeetingsHelperXPCConnectionValidator()
    let verdict = validator.validate(
        signingInfo: MeetingsHelperXPCSigningInfo(
            teamIdentifier: "UDZLCK86PY",
            bundleIdentifier: "com.kacperpietrzyk.nexus.meetings-helper"
        )
    )

    #expect(verdict == .accepted)
}

@Test func xpcValidatorRejectsWrongTeam() {
    let validator = MeetingsHelperXPCConnectionValidator()
    let verdict = validator.validate(
        signingInfo: MeetingsHelperXPCSigningInfo(
            teamIdentifier: "TEAMOTHER",
            bundleIdentifier: "com.kacperpietrzyk.Nexus.Mac"
        )
    )

    #expect(verdict == .rejected)
}

@Test func xpcValidatorRejectsWrongBundle() {
    let validator = MeetingsHelperXPCConnectionValidator()
    let verdict = validator.validate(
        signingInfo: MeetingsHelperXPCSigningInfo(
            teamIdentifier: "UDZLCK86PY",
            bundleIdentifier: "com.example.Other"
        )
    )

    #expect(verdict == .rejected)
}

@Test func xpcValidatorRejectsUnavailableSigningInfoByDefault() {
    let validator = MeetingsHelperXPCConnectionValidator()

    #expect(validator.validate(signingInfo: nil) == .rejected)
}
