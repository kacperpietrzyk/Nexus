import Foundation
import Testing

@testable import NexusMCPSidecar

@Suite("ToolManifestCache")
struct ToolManifestCacheTests {
    @Test("decodes manifest from JSON Data")
    func decode() throws {
        let json = Data(
            """
            {
              "protocol_version": "1.0",
              "tools": [
                {
                  "name": "tasks.get",
                  "description": "Fetch a task",
                  "input_schema": { "type": "object", "properties": {}, "required": [] }
                }
              ]
            }
            """.utf8
        )

        let cache = try ToolManifestCache(from: json)

        #expect(cache.protocolVersion == "1.0")
        #expect(cache.tools.count == 1)
        #expect(cache.tools.first?.name == "tasks.get")
        #expect(cache.tools.first?.inputSchema?["type"] as? String == "object")
    }

    @Test("rejects mismatched major protocol version")
    func majorMismatch() {
        let json = Data(#"{ "protocol_version": "2.0", "tools": [] }"#.utf8)

        #expect(throws: Error.self) {
            _ = try ToolManifestCache(from: json)
        }
    }

    @Test("accepts minor version difference with warning flag")
    func minorMismatch() throws {
        let json = Data(#"{ "protocol_version": "1.5", "tools": [] }"#.utf8)

        let cache = try ToolManifestCache(from: json)

        #expect(cache.hasMinorVersionMismatch)
    }
}
