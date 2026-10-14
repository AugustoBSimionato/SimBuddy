import AgentCore
import AgentMCP
import Foundation
import MCP
import Testing

@Test func mcpInitializesListsToolsAndForwardsIdentifiedRequests() async throws {
    let directory = "/private/tmp/simbuddy-mcp-test-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let path = directory + "/s"
    let bridge = AgentSocketServer(path: path)
    try bridge.start { request in
        if request.method == "execute_operation" {
            return .init("\(request.clientName):\(request.input?.operation ?? "missing"):\(request.sessionID)")
        }
        return .init("Monitoring disabled.", isError: request.method != "disconnect")
    }
    defer { bridge.stop() }
    let transports = await InMemoryTransport.createConnectedPair()
    let serverTask = Task { await SimBuddyMCPServer.run(transport: transports.server, bridgePath: path) }
    let client = Client(name: "Integration test", version: "1")
    _ = try await client.connect(transport: transports.client)
    let tools = try await client.listTools().tools
    #expect(Set(tools.map(\.name)) == ["list_simulators", "describe_operations", "execute_operation", "run_tests", "get_operation", "cancel_operation"])
    let result = try await client.callTool(name: "execute_operation", arguments: ["operation": .string("boot"), "devices": .array([.string("11111111-1111-1111-1111-111111111111")])])
    #expect(result.isError != true)
    if case .text(let value, _, _) = result.content[0] { #expect(value.hasPrefix("Integration test:boot:")) }
    else { Issue.record("Expected text response") }
    let invalid = try await client.callTool(name: "execute_operation", arguments: ["operation": .string("boot"), "shell": .string("sh")])
    #expect(invalid.isError == true)
    let disabled = try await client.callTool(name: "list_simulators")
    #expect(disabled.isError == true)
    await client.disconnect()
    await serverTask.value
}

@Test func mcpReturnsActionableErrorWhenAppIsClosed() async throws {
    let transports = await InMemoryTransport.createConnectedPair()
    let serverTask = Task { await SimBuddyMCPServer.run(transport: transports.server, bridgePath: "/private/tmp/simbuddy-missing-\(UUID().uuidString)") }
    let client = Client(name: "Closed app test", version: "1")
    _ = try await client.connect(transport: transports.client)
    let result = try await client.callTool(name: "list_simulators")
    #expect(result.isError == true)
    if case .text(let value, _, _) = result.content[0] { #expect(value.contains("SimBuddy is not running")) }
    await client.disconnect()
    await serverTask.value
}
