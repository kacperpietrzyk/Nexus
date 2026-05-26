import Testing

@testable import NexusUI

@Test func fontRegistration_registersEightGeistFiles() {
    let files = NexusFontRegistration.fontFiles
    #expect(files.count == 8)
    #expect(
        Set(files) == [
            "Geist-Regular",
            "Geist-Medium",
            "Geist-SemiBold",
            "Geist-Bold",
            "GeistMono-Regular",
            "GeistMono-Medium",
            "GeistMono-SemiBold",
            "GeistMono-Bold",
        ])
}

@Test func fontRegistration_doesNotReferencePreviousFontFamilies() {
    let files = NexusFontRegistration.fontFiles.joined(separator: " ")
    #expect(!files.contains("Inter"))
    #expect(!files.contains("InterTight"))
    #expect(!files.contains("JetBrains"))
    #expect(!files.contains("JetBrainsMono"))
}
