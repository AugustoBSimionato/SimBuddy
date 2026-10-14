import AgentCore
import Foundation
import MCP

public enum SimBuddyMCPServer {
    public static func run(transport: any Transport = StdioTransport(), bridgePath: String = AgentSocket.path) async {
        let connection = BridgeConnection(path: bridgePath)
        let server = Server(name: "SimBuddy", version: "1.0.0",
                            instructions: "Use SimBuddy for simulator operations. Protection only covers this integration. Inspect describe_operations before executing. Client names are self-reported. Tests may modify or restart a simulator internally.",
                            capabilities: .init(tools: .init()), configuration: .strict)
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: tools)
        }
        await server.withMethodHandler(CallTool.self) { params in
            do {
                let arguments = params.arguments ?? [:]
                let method = params.name
                guard tools.contains(where: { $0.name == method }) else { throw AgentFailure("Unknown tool.") }
                let allowed: Set<String> = method == "execute_operation" ? ["operation", "devices", "parameters"] : method == "run_tests" ? ["devices", "parameters"] : ["get_operation", "cancel_operation"].contains(method) ? ["operationID"] : []
                guard Set(arguments.keys).isSubset(of: allowed) else { throw AgentFailure("Unknown tool argument.") }
                var input: AgentOperationInput?
                var operationID: UUID?
                if ["execute_operation", "run_tests"].contains(method) {
                    let operation = method == "run_tests" ? "test" : arguments["operation"]?.stringValue
                    guard let operation else { throw AgentFailure("operation is required.") }
                    guard operation != "test" || method == "run_tests" else { throw AgentFailure("Use run_tests for Xcode tests.") }
                    let devices = try decode([String].self, from: arguments["devices"] ?? .array([]))
                    let parameters = try decode([String: String].self, from: arguments["parameters"] ?? .object([:]))
                    input = .init(operation: operation, devices: devices, parameters: parameters)
                } else if ["get_operation", "cancel_operation"].contains(method) {
                    guard let raw = arguments["operationID"]?.stringValue, let id = UUID(uuidString: raw) else { throw AgentFailure("A valid operationID is required.") }
                    operationID = id
                }
                let response = try await connection.call(method: method, input: input, operationID: operationID)
                return .init(content: [.text(text: response.text, annotations: nil, _meta: nil)], isError: response.isError)
            } catch {
                return .init(content: [.text(text: error.localizedDescription, annotations: nil, _meta: nil)], isError: true)
            }
        }
        do {
            try await server.start(transport: transport) { info, _ in
                await connection.identify(info.name)
            }
            let heartbeat = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(10))
                    if Task.isCancelled { break }
                    _ = try? await connection.call(method: "heartbeat")
                }
            }
            await server.waitUntilCompleted()
            heartbeat.cancel()
            _ = try? await connection.call(method: "disconnect")
            await server.stop()
        } catch {
            try? FileHandle.standardError.write(contentsOf: Data("SimBuddy MCP: \(error.localizedDescription)\n".utf8))
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from value: Value) throws -> T {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(value))
    }

    private static func object(_ properties: [String: Value] = [:], required: [String] = []) -> Value {
        .object(["type": .string("object"), "properties": .object(properties),
                 "required": .array(required.map(Value.string)), "additionalProperties": .bool(false)])
    }
    private static let string: Value = .object(["type": .string("string")])
    private static let devices: Value = .object(["type": .string("array"), "items": string,
        "description": .string("Explicit simulator UDIDs. 'all' and 'booted' expand to known devices before authorization. Tests/captures require one device.")])
    private static let parameters: Value = .object(["type": .string("object"), "additionalProperties": string,
        "description": .string("Named string parameters from describe_operations. File paths must be absolute. Test filters are comma-separated.")])

    private static let tools: [Tool] = [
        Tool(name: "list_simulators", description: "List available simulators with persisted protections.", inputSchema: object()),
        Tool(name: "describe_operations", description: "List supported operations, categories and required/optional parameters. Rules can only be changed in the app.", inputSchema: object()),
        Tool(name: "execute_operation", description: "Queue a classified simctl operation after checking every affected simulator. Returns operationID. No arbitrary commands or runtime changes.", inputSchema: object([
            "operation": .object(["type": .string("string"), "enum": .array(OperationCatalog.definitions.filter { $0.name != "test" }.map { .string($0.name) })]),
            "devices": devices, "parameters": parameters
        ], required: ["operation"])),
        Tool(name: "run_tests", description: "Run xcodebuild test or test-without-building on one explicit simulator. Parameters: projectPath, scheme, optional action, onlyTesting, skipTesting. Parallel testing is disabled. Xcode/scripts may change the destination internally.", inputSchema: object([
            "devices": devices, "parameters": parameters
        ], required: ["devices", "parameters"])),
        Tool(name: "get_operation", description: "Get status, bounded output and xcresult path for an operation in this session.", inputSchema: object(["operationID": string], required: ["operationID"])),
        Tool(name: "cancel_operation", description: "Cancel a queued operation or stop a running process group belonging to this session. Cancelling recordVideo finalizes the recording.", inputSchema: object(["operationID": string], required: ["operationID"]))
    ]
}

private actor BridgeConnection {
    let sessionID = UUID()
    var clientName = "MCP client"
    let path: String
    init(path: String) { self.path = path }
    func identify(_ name: String) async {
        clientName = String(name.prefix(120))
        _ = try? await call(method: "heartbeat")
    }
    func call(method: String, input: AgentOperationInput? = nil, operationID: UUID? = nil) async throws -> AgentBridgeResponse {
        try await AgentSocket.request(.init(method: method, sessionID: sessionID, clientName: clientName, input: input, operationID: operationID), path: path)
    }
}
