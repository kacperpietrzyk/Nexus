import Foundation
import Testing

@testable import NexusMCPSidecar

@Suite("MCPServer smoke")
struct MCPServerSmokeTests {
    @Test("MCPServer initializes with a client")
    func initialize() {
        let client = XPCClient()
        let server = MCPServer(client: client)

        _ = server
    }

    @Test("wraps non-object structuredContent in object result")
    func wrapsStructuredContent() throws {
        let arrayData = Data(#"[{"id":"1"}]"#.utf8)
        let stringData = Data(#""ok""#.utf8)
        let objectData = Data(#"{"id":"1"}"#.utf8)

        #expect(try MCPServer.structuredObject(from: arrayData).objectValue?["result"]?.arrayValue?.count == 1)
        #expect(try MCPServer.structuredObject(from: stringData).objectValue?["result"]?.stringValue == "ok")
        #expect(try MCPServer.structuredObject(from: objectData).objectValue?["id"]?.stringValue == "1")
    }
}
