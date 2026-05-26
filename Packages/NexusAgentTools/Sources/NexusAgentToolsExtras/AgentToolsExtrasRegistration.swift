import Foundation
import NexusAgentTools

public enum AgentToolsAll {
    public static func tools() -> [any AgentTool] {
        CoreTaskTools.all() + NexusAgentToolsExtras.tools()
    }
}
