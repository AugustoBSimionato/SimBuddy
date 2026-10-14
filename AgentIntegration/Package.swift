// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SimBuddyAgents",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "AgentCore", targets: ["AgentCore"]),
        .library(name: "AgentMCP", targets: ["AgentMCP"]),
        .executable(name: "simbuddy-mcp", targets: ["SimBuddyMCP"])
    ],
    dependencies: [.package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1")],
    targets: [
        .target(name: "AgentCore"),
        .target(name: "AgentMCP", dependencies: ["AgentCore", .product(name: "MCP", package: "swift-sdk")]),
        .executableTarget(name: "SimBuddyMCP", dependencies: ["AgentMCP"])
    ]
)
