import Foundation
import Testing

@testable import NexusAgentTools

struct AttachmentIngestPolicyTests {
    @Test("rejects a relative path")
    func rejectsRelative() {
        #expect(throws: AgentError.self) {
            _ = try AttachmentIngestPolicy.resolve(
                source: "relative/x.png",
                allowedRoot: URL(fileURLWithPath: "/tmp")
            )
        }
    }

    @Test("rejects a path escaping the allowed root")
    func rejectsEscape() {
        #expect(throws: AgentError.self) {
            _ = try AttachmentIngestPolicy.resolve(
                source: "/etc/passwd",
                allowedRoot: URL(fileURLWithPath: "/tmp")
            )
        }
    }

    @Test("accepts an absolute path inside the allowed root")
    func acceptsInside() throws {
        let url = try AttachmentIngestPolicy.resolve(
            source: "/tmp/sub/x.png",
            allowedRoot: URL(fileURLWithPath: "/tmp")
        )
        // `/tmp` resolves to `/private/tmp` on macOS via symlink; the prefix check
        // holds after `resolvingSymlinksInPath` because both sides are resolved.
        #expect(url.path.hasSuffix("/sub/x.png"))
    }

    @Test("accepts a file:// URL form")
    func acceptsFileURL() throws {
        let url = try AttachmentIngestPolicy.resolve(
            source: "file:///tmp/x.png",
            allowedRoot: URL(fileURLWithPath: "/tmp")
        )
        #expect(url.path.hasSuffix("/x.png"))
    }
}
