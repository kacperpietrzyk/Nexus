import Foundation
import SwiftData
import Testing

@testable import NexusCore
@testable import NotesFeature

@MainActor
private func makeRepo() throws -> NoteRepository {
    let schema = Schema([TaskItem.self, Note.self, Label.self, Person.self, Link.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [config])
    return NoteRepository(context: ModelContext(container))
}

/// Writes `files` ([relativePath: contents]) into a fresh temp vault dir, returns its URL.
private func makeVault(_ files: [String: String]) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("vault-\(UUID().uuidString)", isDirectory: true)
    for (rel, body) in files {
        let url = root.appendingPathComponent(rel)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try body.write(to: url, atomically: true, encoding: .utf8)
    }
    return root
}

// MARK: - Pure derivations

@Test func title_stripsMdExtension_preservingAmpersandAndSpaces() {
    #expect(ObsidianVaultImporter.title(forFileName: "CrowdStrike Strategy & Roadmap.md")
        == "CrowdStrike Strategy & Roadmap")
    #expect(ObsidianVaultImporter.title(forFileName: "Plain.md") == "Plain")
}

@Test func body_stripsLeadingFrontmatter() {
    let content = "---\ntitle: X\ntags: []\n---\n\nHello world\n\nSecond para"
    #expect(ObsidianVaultImporter.body(strippingFrontmatterFrom: content)
        == "Hello world\n\nSecond para")
}

@Test func body_withoutFrontmatter_isUnchanged() {
    let content = "# Heading\n\nbody text"
    #expect(ObsidianVaultImporter.body(strippingFrontmatterFrom: content) == content)
}

@Test func body_nonLeadingDivider_isNotStripped() {
    // A `---` that is NOT the first line is a real divider, not frontmatter.
    let content = "intro\n\n---\n\nafter divider"
    #expect(ObsidianVaultImporter.body(strippingFrontmatterFrom: content) == content)
}

@Test func body_unterminatedFrontmatter_isUnchanged() {
    let content = "---\ntitle: X\n\nno closing fence"
    #expect(ObsidianVaultImporter.body(strippingFrontmatterFrom: content) == content)
}

@Test func folderPath_nested_isNormalizedDir() {
    #expect(ObsidianVaultImporter.folderPath(
        forRelativePath: "20 - Softinet Internal/Strategy/Talking Points.md")
        == "20 - Softinet Internal/Strategy")
}

@Test func folderPath_rootFile_isNil() {
    #expect(ObsidianVaultImporter.folderPath(forRelativePath: "START HERE - INDEX.md") == nil)
}

@Test func role_templatesFolder_isTemplate() {
    #expect(ObsidianVaultImporter.role(forRelativePath: "90 - Templates/Project Hub.md") == .template)
}

@Test func role_otherFolder_isFree() {
    #expect(ObsidianVaultImporter.role(forRelativePath: "10 - Klienci/ACME.md") == .free)
}

// MARK: - Plan (pure dedup)

@Test func plan_newNote_isCreated_existingNote_isSkipped() {
    let fresh = DiscoveredNote(relativePath: "10 - Klienci/ACME.md")
    let landed = DiscoveredNote(relativePath: "20 - Softinet Internal/Strategy/Talking Points.md")
    let existing: Set<NoteKey> = [
        NoteKey(title: "Talking Points", folderPath: "20 - Softinet Internal/Strategy")
    ]
    let plan = ObsidianVaultImporter().plan(discovered: [fresh, landed], existing: existing)
    #expect(plan.toCreate.map(\.relativePath) == [fresh.relativePath])
    #expect(plan.toSkip.map(\.relativePath) == [landed.relativePath])
}

@Test func plan_collisionTitles_inDifferentFolders_stayDistinct() {
    let hubA = DiscoveredNote(relativePath: "Projects/Vanguard/Project Hub.md")
    let hubB = DiscoveredNote(relativePath: "20 - Softinet Internal/Events/Konferencja Maj 2026/Project Hub.md")
    // Only hubA already exists -> hubB must still be created.
    let existing: Set<NoteKey> = [NoteKey(title: "Project Hub", folderPath: "Projects/Vanguard")]
    let plan = ObsidianVaultImporter().plan(discovered: [hubA, hubB], existing: existing)
    #expect(plan.toSkip.map(\.relativePath) == [hubA.relativePath])
    #expect(plan.toCreate.map(\.relativePath) == [hubB.relativePath])
}

// MARK: - Discovery

@Test func discover_findsMarkdownRecursively_skippingHiddenAndNonMarkdown() throws {
    let vault = try makeVault([
        "Root.md": "x",
        "A/Nested.md": "y",
        "A/image.png": "binary",
        ".obsidian/config.md": "should be skipped"
    ])
    defer { try? FileManager.default.removeItem(at: vault) }
    let found = try ObsidianVaultImporter.discover(vaultRoot: vault).map(\.relativePath)
    #expect(found == ["A/Nested.md", "Root.md"])
}

// MARK: - Execute (integration, real repo, idempotent)

@MainActor
@Test func execute_createsNotes_withTitleFolderRole_andIsIdempotent() async throws {
    let vault = try makeVault([
        "20 - Softinet Internal/Strategy/Talking Points.md": "---\ntitle: ignored\n---\n\nBoard talking points body",
        "90 - Templates/Project Hub.md": "Template body",
        "Root Note.md": "at the root"
    ])
    defer { try? FileManager.default.removeItem(at: vault) }
    let repo = try makeRepo()
    let importer = ObsidianVaultImporter()

    let discovered = try ObsidianVaultImporter.discover(vaultRoot: vault)
    let plan1 = importer.plan(
        discovered: discovered, existing: try ObsidianVaultImporter.existingKeys(in: repo))
    let result1 = try await importer.execute(
        plan: plan1, repo: repo, vaultRoot: vault, progress: { _ in })

    #expect(result1.created == 3)
    #expect(result1.skipped == 0)
    #expect(result1.failed == 0)

    let all = try repo.context.fetch(FetchDescriptor<Note>())
    let talking = try #require(all.first { $0.title == "Talking Points" })
    #expect(talking.folderPath == "20 - Softinet Internal/Strategy")
    #expect(talking.role == .free)
    #expect(talking.plainText.contains("Board talking points body"))
    // Frontmatter must NOT leak into the body.
    #expect(!talking.plainText.contains("ignored"))

    let template = try #require(all.first { $0.title == "Project Hub" })
    #expect(template.role == .template)
    #expect(template.folderPath == "90 - Templates")

    let root = try #require(all.first { $0.title == "Root Note" })
    #expect(root.folderPath == nil)

    // Second run: every note already exists -> all skipped, nothing duplicated.
    let plan2 = importer.plan(
        discovered: discovered, existing: try ObsidianVaultImporter.existingKeys(in: repo))
    let result2 = try await importer.execute(
        plan: plan2, repo: repo, vaultRoot: vault, progress: { _ in })
    #expect(result2.created == 0)
    #expect(result2.skipped == 3)
    #expect(try repo.context.fetch(FetchDescriptor<Note>()).count == 3)
}
