import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgentTools

@Suite("NotesTools frontmatter import")
struct NotesToolsFrontmatterImportTests {
    @MainActor
    @Test("create strips exported markdown frontmatter before parsing blocks")
    func createStripsExportedFrontmatter() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let document = """
            ---
            id: 11111111-1111-1111-1111-111111111111
            kind: note
            title: "Imported note"
            links: []
            ---

            # Imported note

            Real body.
            """
        let result = try await NotesCreateTool().call(
            args: .object([
                "title": .string("Imported note"),
                "body": .string(document),
            ]),
            context: fixture.context
        )
        let dto = try TasksToolJSON.decode(NoteDTO.self, from: result)

        #expect(dto.body.contains("Real body."))
        #expect(dto.body.contains("11111111-1111-1111-1111-111111111111") == false)
        #expect(dto.body.contains("links: []") == false)

        let id = try #require(UUID(uuidString: dto.id))
        let note = try #require(try fixture.context.noteRepository.find(id: id))
        #expect(note.plainText.contains("Real body."))
        #expect(note.plainText.contains("11111111-1111-1111-1111-111111111111") == false)
        #expect(note.plainText.contains("links: []") == false)
    }

    @MainActor
    @Test("create applies exported frontmatter metadata when fields are omitted")
    func createAppliesExportedFrontmatterMetadata() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let document = """
            ---
            title: "Imported metadata"
            role: dailyNote
            tags:
              - obsidian
              - project
            links:
              - toKind: task
                toID: aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
                linkKind: containsTask
            ---

            Real body.
            """
        let result = try await NotesCreateTool().call(
            args: .object(["body": .string(document)]),
            context: fixture.context
        )
        let dto = try TasksToolJSON.decode(NoteDTO.self, from: result)

        #expect(dto.title == "Imported metadata")
        #expect(dto.role == "dailyNote")
        #expect(dto.tags == ["obsidian", "project"])
        #expect(dto.body.contains("Real body."))
        #expect(dto.body.contains("toKind: task") == false)
    }

    @MainActor
    @Test("create restores explicit frontmatter links and skips reconciler-owned links")
    func createRestoresExplicitFrontmatterLinks() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let projectID = UUID()
        let taskID = UUID()
        let document = """
            ---
            title: "Imported links"
            links:
              - toKind: project
                toID: \(projectID.uuidString)
                linkKind: source
              - toKind: task
                toID: \(taskID.uuidString)
                linkKind: containsTask
            ---

            Real body.
            """
        let result = try await NotesCreateTool().call(
            args: .object(["body": .string(document)]),
            context: fixture.context
        )
        let dto = try TasksToolJSON.decode(NoteDTO.self, from: result)
        let noteID = try #require(UUID(uuidString: dto.id))

        let links = try fixture.context.linkRepository.outgoing(from: (.note, noteID))
        #expect(links.count == 1)
        #expect(links.first?.toKind == .project)
        #expect(links.first?.toID == projectID)
        #expect(links.first?.linkKind == .source)
    }
}

@Suite("NotesTools")
struct NotesToolsTests {
    // MARK: - note.create

    @MainActor
    @Test("create from markdown returns note with rendered body and plain cache")
    func createFromMarkdown() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let args = JSONValue.object([
            "title": .string("My note"),
            "body": .string("# Heading\n\nA paragraph."),
            "tags": .array([.string("kb"), .string("ideas")]),
        ])

        let result = try await NotesCreateTool().call(args: args, context: fixture.context)
        let dto = try TasksToolJSON.decode(NoteDTO.self, from: result)

        #expect(dto.title == "My note")
        #expect(dto.role == "free")
        #expect(dto.tags == ["kb", "ideas"])
        #expect(dto.format == "markdown")
        #expect(dto.body.contains("Heading"))
        #expect(dto.body.contains("A paragraph."))

        // The persisted note's plainText cache is consistent with the blob.
        let id = try #require(UUID(uuidString: dto.id))
        let fetched = try fixture.context.noteRepository.find(id: id)
        let note = try #require(fetched)
        #expect(note.plainText.contains("Heading"))
        #expect(note.plainText.contains("A paragraph."))
    }

    @MainActor
    @Test("create with role applies the typed role")
    func createWithRole() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let args = JSONValue.object([
            "title": .string("Daily"),
            "role": .string("dailyNote"),
            "body": .string("today"),
        ])

        let result = try await NotesCreateTool().call(args: args, context: fixture.context)
        let dto = try TasksToolJSON.decode(NoteDTO.self, from: result)
        #expect(dto.role == "dailyNote")
    }

    @MainActor
    @Test("create rejects an unknown role")
    func createRejectsUnknownRole() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let args = JSONValue.object([
            "title": .string("x"),
            "role": .string("bogus"),
        ])
        await #expect(throws: AgentError.self) {
            _ = try await NotesCreateTool().call(args: args, context: fixture.context)
        }
    }

    // MARK: - checkbox → Task seam (marquee)

    @MainActor
    @Test("create with a checkbox materializes a TaskItem and a containsTask Link")
    func createCheckboxMaterializesTask() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let args = JSONValue.object([
            "title": .string("seam"),
            "body": .string("- [ ] buy milk"),
        ])

        let result = try await NotesCreateTool().call(args: args, context: fixture.context)
        let dto = try TasksToolJSON.decode(NoteDTO.self, from: result)
        let noteID = try #require(UUID(uuidString: dto.id))
        let modelContext = fixture.context.modelContext.context

        // A real TaskItem was created with the checkbox text.
        let tasks = try modelContext.fetch(FetchDescriptor<TaskItem>())
            .filter { $0.deletedAt == nil }
        #expect(tasks.map(\.title) == ["buy milk"])

        // A containsTask Link from the note to that task exists.
        let containsLinks = try modelContext.fetch(FetchDescriptor<Link>())
            .filter { $0.fromID == noteID && $0.linkKind == .containsTask }
        #expect(containsLinks.count == 1)
        #expect(containsLinks.first?.toID == tasks.first?.id)
    }

    @MainActor
    @Test("reconcile-on-load is idempotent: a second pass does not change the graph")
    func reconcileIsIdempotent() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let args = JSONValue.object([
            "body": .string("- [ ] one\n- [ ] two")
        ])
        let result = try await NotesCreateTool().call(args: args, context: fixture.context)
        let dto = try TasksToolJSON.decode(NoteDTO.self, from: result)
        let noteID = try #require(UUID(uuidString: dto.id))
        let modelContext = fixture.context.modelContext.context

        let tasksAfterCreate = try modelContext.fetch(FetchDescriptor<TaskItem>())
            .filter { $0.deletedAt == nil }.count
        let linksAfterCreate = try modelContext.fetch(FetchDescriptor<Link>())
            .filter { $0.fromID == noteID }.count
        #expect(tasksAfterCreate == 2)
        #expect(linksAfterCreate == 2)

        // Recompute-on-load again — no drift.
        let fetched = try fixture.context.noteRepository.find(id: noteID)
        let note = try #require(fetched)
        let changed = try fixture.context.noteRepository.reconcileOnLoad(note)
        #expect(changed == false)

        let tasksAfterReload = try modelContext.fetch(FetchDescriptor<TaskItem>())
            .filter { $0.deletedAt == nil }.count
        let linksAfterReload = try modelContext.fetch(FetchDescriptor<Link>())
            .filter { $0.fromID == noteID }.count
        #expect(tasksAfterReload == 2)
        #expect(linksAfterReload == 2)
    }

    // MARK: - Checkbox identity round-trip

    /// MCP markdown reads include a stable task-ref marker that `note.update`
    /// parses back into the same todo block. A get-markdown → update-with-same-
    /// markdown cycle must not orphan the original task or mint a duplicate.
    @MainActor
    @Test("markdown round-trip update preserves checkbox task identity")
    func updateMarkdownRoundTripPreservesTaskIdentity() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let modelContext = fixture.context.modelContext.context

        let created = try await NotesCreateTool().call(
            args: .object(["body": .string("- [ ] buy milk")]),
            context: fixture.context
        )
        let id = try #require(UUID(uuidString: TasksToolJSON.decode(NoteDTO.self, from: created).id))

        let originalTasks = try modelContext.fetch(FetchDescriptor<TaskItem>())
            .filter { $0.deletedAt == nil }
        #expect(originalTasks.count == 1)
        let originalTaskID = try #require(originalTasks.first?.id)

        // Round-trip: read the markdown the tool produced, write it straight back.
        let gotten = try await NotesGetTool().call(
            args: .object(["id": .string(id.uuidString), "format": .string("markdown")]),
            context: fixture.context
        )
        let markdown = try TasksToolJSON.decode(NoteDTO.self, from: gotten).body
        #expect(markdown.contains("nexus-task:\(originalTaskID.uuidString)"))
        _ = try await NotesUpdateTool().call(
            args: .object(["id": .string(id.uuidString), "body": .string(markdown)]),
            context: fixture.context
        )

        let afterTasks = try modelContext.fetch(FetchDescriptor<TaskItem>())
            .filter { $0.deletedAt == nil }
        let liveContainsTargets = try modelContext.fetch(FetchDescriptor<Link>())
            .filter { $0.fromID == id && $0.linkKind == .containsTask }
            .map(\.toID)
        #expect(afterTasks.count == 1)
        #expect(liveContainsTargets.count == 1)
        #expect(liveContainsTargets.first == originalTaskID)
    }

    // MARK: - note.update

    @MainActor
    @Test("update body replaces content and refreshes plain cache")
    func updateBody() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let created = try await NotesCreateTool().call(
            args: .object(["body": .string("original")]),
            context: fixture.context
        )
        let id = try #require(UUID(uuidString: TasksToolJSON.decode(NoteDTO.self, from: created).id))

        _ = try await NotesUpdateTool().call(
            args: .object(["id": .string(id.uuidString), "body": .string("replaced text")]),
            context: fixture.context
        )

        let fetched = try fixture.context.noteRepository.find(id: id)
        let note = try #require(fetched)
        #expect(note.plainText.contains("replaced text"))
        #expect(!note.plainText.contains("original"))
    }

    @MainActor
    @Test("update leaves omitted fields untouched")
    func updateOmitDoesNotClear() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let created = try await NotesCreateTool().call(
            args: .object([
                "title": .string("keep title"),
                "tags": .array([.string("a")]),
                "body": .string("keep body"),
            ]),
            context: fixture.context
        )
        let id = try #require(UUID(uuidString: TasksToolJSON.decode(NoteDTO.self, from: created).id))

        // Update only the title; tags + body must survive.
        _ = try await NotesUpdateTool().call(
            args: .object(["id": .string(id.uuidString), "title": .string("new title")]),
            context: fixture.context
        )

        let fetched = try fixture.context.noteRepository.find(id: id)
        let note = try #require(fetched)
        #expect(note.title == "new title")
        #expect(note.tags == ["a"])
        #expect(note.plainText.contains("keep body"))
    }

    @MainActor
    @Test("update of a missing note throws notFound")
    func updateMissingThrows() async throws {
        let fixture = try await InMemoryAgentContext.make()
        await #expect(throws: AgentError.self) {
            _ = try await NotesUpdateTool().call(
                args: .object(["id": .string(UUID().uuidString), "title": .string("x")]),
                context: fixture.context
            )
        }
    }

    // MARK: - note.get

    @MainActor
    @Test("get renders markdown, html, and plain")
    func getRendersFormats() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let created = try await NotesCreateTool().call(
            args: .object(["title": .string("formats"), "body": .string("# Title\n\nbody text")]),
            context: fixture.context
        )
        let id = try #require(UUID(uuidString: TasksToolJSON.decode(NoteDTO.self, from: created).id))

        let md = try await NotesGetTool().call(
            args: .object(["id": .string(id.uuidString), "format": .string("markdown")]),
            context: fixture.context
        )
        #expect(try TasksToolJSON.decode(NoteDTO.self, from: md).body.contains("# Title"))

        let html = try await NotesGetTool().call(
            args: .object(["id": .string(id.uuidString), "format": .string("html")]),
            context: fixture.context
        )
        let htmlDTO = try TasksToolJSON.decode(NoteDTO.self, from: html)
        #expect(htmlDTO.format == "html")
        #expect(htmlDTO.body.contains("<h1"))

        let plain = try await NotesGetTool().call(
            args: .object(["id": .string(id.uuidString), "format": .string("plain")]),
            context: fixture.context
        )
        let plainDTO = try TasksToolJSON.decode(NoteDTO.self, from: plain)
        #expect(plainDTO.body.contains("body text"))
        #expect(!plainDTO.body.contains("<h1"))
    }

    // MARK: - html body escape-hatch

    @MainActor
    @Test("html body is stored verbatim in an html(raw) block")
    func htmlBodyVerbatim() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let raw = "<div class=\"x\">hi <b>there</b></div>"
        let created = try await NotesCreateTool().call(
            args: .object(["body": .string(raw), "body_format": .string("html")]),
            context: fixture.context
        )
        let id = try #require(UUID(uuidString: TasksToolJSON.decode(NoteDTO.self, from: created).id))

        let fetched = try fixture.context.noteRepository.find(id: id)
        let note = try #require(fetched)
        let blocks = try NoteContentCoder.decode(note.contentData)
        #expect(blocks.count == 1)
        if case .html(let stored) = blocks.first?.kind {
            #expect(stored == raw)
        } else {
            Issue.record("expected a single html(raw) block, got \(String(describing: blocks.first?.kind))")
        }
    }

    // MARK: - note.list

    @MainActor
    @Test("list filters by role and tags, newest first")
    func listFilters() async throws {
        let fixture = try await InMemoryAgentContext.make()
        _ = try await NotesCreateTool().call(
            args: .object(["title": .string("free a"), "tags": .array([.string("x")])]),
            context: fixture.context
        )
        _ = try await NotesCreateTool().call(
            args: .object(["title": .string("daily"), "role": .string("dailyNote")]),
            context: fixture.context
        )

        // Filter by role.
        let dailyResult = try await NotesListTool().call(
            args: .object(["role": .string("dailyNote")]),
            context: fixture.context
        )
        let daily = try TasksToolJSON.decode([NoteDTO].self, from: dailyResult)
        #expect(daily.map(\.title) == ["daily"])

        // Filter by tag.
        let taggedResult = try await NotesListTool().call(
            args: .object(["tags": .array([.string("x")])]),
            context: fixture.context
        )
        let tagged = try TasksToolJSON.decode([NoteDTO].self, from: taggedResult)
        #expect(tagged.map(\.title) == ["free a"])
    }

    // MARK: - note.search

    @MainActor
    @Test("search matches title and plain content, case-insensitively")
    func searchMatches() async throws {
        let fixture = try await InMemoryAgentContext.make()
        _ = try await NotesCreateTool().call(
            args: .object(["title": .string("Groceries"), "body": .string("buy MILK and eggs")]),
            context: fixture.context
        )
        _ = try await NotesCreateTool().call(
            args: .object(["title": .string("Other"), "body": .string("unrelated")]),
            context: fixture.context
        )

        let result = try await NotesSearchTool().call(
            args: .object(["query": .string("milk")]),
            context: fixture.context
        )
        let hits = try TasksToolJSON.decode([NoteDTO].self, from: result)
        #expect(hits.map(\.title) == ["Groceries"])
    }

    @MainActor
    @Test("search without a query throws validation")
    func searchRequiresQuery() async throws {
        let fixture = try await InMemoryAgentContext.make()
        await #expect(throws: AgentError.self) {
            _ = try await NotesSearchTool().call(args: .object([:]), context: fixture.context)
        }
    }

    // MARK: - note.link

    @MainActor
    @Test("link creates a non-derived edge that survives reconcile")
    func linkCreatesEdge() async throws {
        let project = Project(name: "Proj")
        let fixture = try await InMemoryAgentContext.make()
        fixture.context.modelContext.context.insert(project)
        try fixture.context.modelContext.context.save()

        let created = try await NotesCreateTool().call(
            args: .object(["title": .string("linker")]),
            context: fixture.context
        )
        let noteID = try #require(UUID(uuidString: TasksToolJSON.decode(NoteDTO.self, from: created).id))

        let linkResult = try await NotesLinkTool().call(
            args: .object([
                "note_id": .string(noteID.uuidString),
                "target_id": .string(project.id.uuidString),
                "target_kind": .string("project"),
                "kind": .string("source"),
            ]),
            context: fixture.context
        )
        #expect(linkResult["status"]?.stringValue == "ok")

        let modelContext = fixture.context.modelContext.context
        func sourceLinks() throws -> [Link] {
            try modelContext.fetch(FetchDescriptor<Link>())
                .filter { $0.fromID == noteID && $0.linkKind == .source }
        }
        #expect(try sourceLinks().count == 1)

        // Reconcile-on-load must NOT prune this non-derived edge.
        let fetched = try fixture.context.noteRepository.find(id: noteID)
        let note = try #require(fetched)
        _ = try fixture.context.noteRepository.reconcileOnLoad(note)
        #expect(try sourceLinks().count == 1)
    }

    @MainActor
    @Test("link is idempotent: a repeat returns the same link")
    func linkIdempotent() async throws {
        let project = Project(name: "Proj")
        let fixture = try await InMemoryAgentContext.make()
        fixture.context.modelContext.context.insert(project)
        try fixture.context.modelContext.context.save()

        let created = try await NotesCreateTool().call(
            args: .object(["title": .string("linker")]),
            context: fixture.context
        )
        let noteID = try #require(UUID(uuidString: TasksToolJSON.decode(NoteDTO.self, from: created).id))
        let args = JSONValue.object([
            "note_id": .string(noteID.uuidString),
            "target_id": .string(project.id.uuidString),
            "target_kind": .string("project"),
            "kind": .string("source"),
        ])

        let first = try await NotesLinkTool().call(args: args, context: fixture.context)
        let second = try await NotesLinkTool().call(args: args, context: fixture.context)
        #expect(first["link_id"]?.stringValue == second["link_id"]?.stringValue)

        let count = try fixture.context.modelContext.context.fetch(FetchDescriptor<Link>())
            .filter { $0.fromID == noteID && $0.linkKind == .source }.count
        #expect(count == 1)
    }

    @MainActor
    @Test("link rejects reconciler-owned kinds")
    func linkRejectsDerivedKinds() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let created = try await NotesCreateTool().call(
            args: .object(["title": .string("linker")]),
            context: fixture.context
        )
        let noteID = try #require(UUID(uuidString: TasksToolJSON.decode(NoteDTO.self, from: created).id))

        for kind in ["containsTask", "embed", "mentions"] {
            await #expect(throws: AgentError.self) {
                _ = try await NotesLinkTool().call(
                    args: .object([
                        "note_id": .string(noteID.uuidString),
                        "target_id": .string(UUID().uuidString),
                        "target_kind": .string("task"),
                        "kind": .string(kind),
                    ]),
                    context: fixture.context
                )
            }
        }
    }

    @MainActor
    @Test("link rejects a hallucinated target instead of minting a dangling edge (A2)")
    func linkValidatesTarget() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let created = try await NotesCreateTool().call(
            args: .object(["title": .string("linker")]),
            context: fixture.context
        )
        let noteID = try #require(UUID(uuidString: TasksToolJSON.decode(NoteDTO.self, from: created).id))

        await #expect(throws: AgentError.self) {
            _ = try await NotesLinkTool().call(
                args: .object([
                    "note_id": .string(noteID.uuidString),
                    "target_id": .string(UUID().uuidString),
                    "target_kind": .string("project"),
                    "kind": .string("source"),
                ]),
                context: fixture.context
            )
        }
        // No edge should have been created.
        let count = try fixture.context.modelContext.context.fetch(FetchDescriptor<Link>())
            .filter { $0.fromID == noteID }.count
        #expect(count == 0)
    }
}
