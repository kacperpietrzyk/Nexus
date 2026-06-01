import Testing

@testable import NexusUI

@Test func fontRegistration_registersEightGeistFiles() {
    let files = NexusFontRegistration.fontFiles
    #expect(files.count == 8)
    #expect(
        Set(files) == [
            "Inter-Regular",
            "Inter-Medium",
            "Inter-SemiBold",
            "Inter-Bold",
            "IBMPlexMono-Regular",
            "IBMPlexMono-Medium",
            "IBMPlexMono-SemiBold",
            "IBMPlexMono-Bold",
        ])
}

@Test func fontRegistration_doesNotReferencePreviousFontFamilies() {
    let files = NexusFontRegistration.fontFiles.joined(separator: " ")
    #expect(!files.contains("Geist"))
    #expect(!files.contains("GeistMono"))
    #expect(!files.contains("JetBrains"))
    #expect(!files.contains("JetBrainsMono"))
}
