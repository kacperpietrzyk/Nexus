import Foundation
import Testing

@testable import NexusCore

@Suite("NoteFolderPath")
struct NoteFolderPathTests {
    @Test("normalizes slashes and per-component whitespace")
    func normalizesSlashesAndWhitespace() {
        #expect(NoteFolderPath.normalize("area/subarea") == "area/subarea")
        #expect(NoteFolderPath.normalize("/area/subarea/") == "area/subarea")
        #expect(NoteFolderPath.normalize("area//subarea") == "area/subarea")
        #expect(NoteFolderPath.normalize("  area / subarea  ") == "area/subarea")
    }

    @Test("drops dot and dot-dot components (never resolves them)")
    func dropsDotComponents() {
        #expect(NoteFolderPath.normalize("./area/../subarea") == "area/subarea")
        #expect(NoteFolderPath.normalize("..") == nil)
        #expect(NoteFolderPath.normalize("./.") == nil)
    }

    @Test("empty input means root (nil)")
    func emptyMeansRoot() {
        #expect(NoteFolderPath.normalize(nil) == nil)
        #expect(NoteFolderPath.normalize("") == nil)
        #expect(NoteFolderPath.normalize("   ") == nil)
        #expect(NoteFolderPath.normalize("///") == nil)
    }
}
