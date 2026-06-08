import Foundation
import Testing

@testable import NexusCore

@Test func frontmatterCoder_encode_emitsKeysInDeclaredOrder() throws {
    let fields: [(String, FrontmatterValue)] = [
        ("id", .string("11111111-1111-1111-1111-111111111111")),
        ("kind", .string("debug")),
        ("createdAt", .date(Date(timeIntervalSince1970: 1_700_000_000))),
        ("updatedAt", .date(Date(timeIntervalSince1970: 1_700_000_500))),
        ("deletedAt", .none),
        ("title", .string("Hello world")),
        ("links", .list([])),
    ]
    let yaml = MarkdownFrontmatterCoder.encode(fields: fields)
    let expected = """
        ---
        id: 11111111-1111-1111-1111-111111111111
        kind: debug
        createdAt: 2023-11-14T22:13:20Z
        updatedAt: 2023-11-14T22:21:40Z
        deletedAt: null
        title: "Hello world"
        links: []
        ---

        """
    #expect(yaml == expected)
}

@Test func frontmatterCoder_encode_listOfDicts_isStable() throws {
    let fields: [(String, FrontmatterValue)] = [
        (
            "links",
            .list([
                .dict([
                    ("toKind", .string("debug")),
                    ("toID", .string("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")),
                    ("linkKind", .string("mentions")),
                ]),
                .dict([
                    ("toKind", .string("debug")),
                    ("toID", .string("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")),
                    ("linkKind", .string("blocks")),
                ]),
            ])
        )
    ]
    let yaml = MarkdownFrontmatterCoder.encode(fields: fields)
    let expected = """
        ---
        links:
          - toKind: debug
            toID: aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
            linkKind: mentions
          - toKind: debug
            toID: bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
            linkKind: blocks
        ---

        """
    #expect(yaml == expected)
}

@Test func frontmatterCoder_decode_roundTripsScalars() throws {
    let source = """
        ---
        id: 11111111-1111-1111-1111-111111111111
        kind: debug
        title: "Hello world"
        deletedAt: null
        ---

        body
        """
    let parsed = try MarkdownFrontmatterCoder.decode(source)
    #expect(parsed.body == "body")
    let fields = Dictionary(uniqueKeysWithValues: parsed.fields.map { ($0.0, $0.1) })
    #expect(fields["id"] == .string("11111111-1111-1111-1111-111111111111"))
    #expect(fields["kind"] == .string("debug"))
    #expect(fields["title"] == .string("Hello world"))
    #expect(fields["deletedAt"] == FrontmatterValue.none)
}

@Test func frontmatterCoder_decode_roundTripsLists() throws {
    let source = """
        ---
        tags:
          - obsidian
          - project
        links:
          - toKind: task
            toID: aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
            linkKind: containsTask
          - toKind: note
            toID: bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
            linkKind: mentions
        ---

        body
        """
    let parsed = try MarkdownFrontmatterCoder.decode(source)

    #expect(parsed.body == "body")
    let fields = Dictionary(uniqueKeysWithValues: parsed.fields.map { ($0.0, $0.1) })
    #expect(fields["tags"] == .list([.string("obsidian"), .string("project")]))
    #expect(
        fields["links"]
            == .list([
                .dict([
                    ("toKind", .string("task")),
                    ("toID", .string("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")),
                    ("linkKind", .string("containsTask")),
                ]),
                .dict([
                    ("toKind", .string("note")),
                    ("toID", .string("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")),
                    ("linkKind", .string("mentions")),
                ]),
            ])
    )
}

@Test func frontmatterCoder_decode_throwsOnMissingClose() {
    let source = """
        ---
        id: x
        body without close
        """
    #expect(throws: MarkdownFrontmatterError.missingClosingDelimiter) {
        try MarkdownFrontmatterCoder.decode(source)
    }
}
