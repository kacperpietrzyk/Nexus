import Foundation

@main
struct NexusMCPSidecarMain {
    static func main() async {
        let client = XPCClient()
        let server = MCPServer(client: client)
        do {
            try await server.start()
        } catch let error as MCPError {
            writeStderr("nexus-mcp fatal: \(error.message) (code \(error.code))")
            exit(1)
        } catch {
            writeStderr("nexus-mcp fatal: \(error)")
            exit(1)
        }
    }

    private static func writeStderr(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}
