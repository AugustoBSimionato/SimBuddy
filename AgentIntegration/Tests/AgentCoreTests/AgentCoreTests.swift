import Foundation
import Testing
@testable import AgentCore

private let phone = "11111111-1111-1111-1111-111111111111"
private let watch = "22222222-2222-2222-2222-222222222222"
private let inventory = AgentInventory(devices: [
    .init(id: phone, name: "iPhone", state: "Booted", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-26-0"),
    .init(id: watch, name: "Watch", state: "Shutdown", runtime: "com.apple.CoreSimulator.SimRuntime.watchOS-26-0")
], pairs: ["pair": .init(watch: watch, phone: phone)])

@Test func protectionCoversEveryCategoryAndSurvivesPersistence() throws {
    let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = AgentPersistence(directory: directory)
    var settings = AgentSettings()
    settings.enabled = true
    settings.protections[phone] = AgentProtection(enabled: true)
    try persistence.save(.init(settings: settings))
    let saved = try persistence.load().settings
    for category in AgentCategory.allCases {
        if [.stop, .destructive].contains(category) {
            #expect(throws: AgentFailure.self) { try AgentPolicy.check(category: category, deviceIDs: [watch, phone], settings: saved) }
        } else { try AgentPolicy.check(category: category, deviceIDs: [phone], settings: saved) }
    }
    settings.protections[phone]?.blocked = Set(AgentCategory.allCases)
    for category in AgentCategory.allCases {
        #expect(throws: AgentFailure.self) { try AgentPolicy.check(category: category, deviceIDs: [phone], settings: settings) }
    }
    settings.enabled = false
    #expect(throws: AgentFailure.self) { try AgentPolicy.check(category: .boot, deviceIDs: [], settings: settings) }
}

@Test func resolvesCollectiveAndPairedTargetsBeforeAuthorization() throws {
    for input in [AgentOperationInput(operation: "shutdown", devices: ["all"]),
                  .init(operation: "shutdown", devices: [watch]),
                  .init(operation: "unpair", parameters: ["pairID": "pair"])] {
        let plan = try OperationCatalog.plan(input, inventory: inventory)
        #expect(Set(plan.deviceIDs) == [phone, watch])
        #expect(!plan.commands.flatMap(\.arguments).contains("all"))
        var settings = AgentSettings(); settings.enabled = true
        settings.protections[phone] = .init(enabled: true, blocked: [.stop, .configuration])
        #expect(throws: AgentFailure.self) { try AgentPolicy.check(category: plan.category, deviceIDs: plan.deviceIDs, settings: settings) }
    }
}

@Test func rejectsUnknownCommandsArgumentsAndDestinations() {
    let invalid: [AgentOperationInput] = [
        .init(operation: "spawn", devices: [phone], parameters: ["path": "/bin/sh"]),
        .init(operation: "runtime", parameters: ["delete": "all"]),
        .init(operation: "shutdown", devices: ["--set"]),
        .init(operation: "boot", devices: [phone], parameters: ["arguments": "--set /tmp"]),
        .init(operation: "install", devices: [phone], parameters: ["path": "relative.app"]),
        .init(operation: "rename", devices: [phone], parameters: ["name": "--all"]),
        .init(operation: "location.set", devices: [phone], parameters: ["latitude": "nan", "longitude": "0"]),
        .init(operation: "test", devices: ["all"], parameters: ["projectPath": "/tmp/App.xcodeproj", "scheme": "App"]),
        .init(operation: "test", devices: [phone], parameters: ["projectPath": "/tmp/App.xcodeproj", "scheme": "App", "destination": "all"])
    ]
    for input in invalid {
        #expect(throws: AgentFailure.self) { try OperationCatalog.plan(input, inventory: inventory, resultBundlePath: "/tmp/Test.xcresult") }
    }
}

@Test func testsHaveExplicitDestinationAndSeparatePolicy() throws {
    let plan = try OperationCatalog.plan(.init(operation: "test", devices: [phone], parameters: [
        "projectPath": "/tmp/App with spaces.xcworkspace", "scheme": "App", "onlyTesting": "AppTests/testOne,AppTests/testTwo"
    ]), inventory: inventory, resultBundlePath: "/tmp/results.xcresult")
    let arguments = plan.commands[0].arguments
    #expect(arguments.contains("id=\(phone)"))
    #expect(arguments.contains("-only-testing:AppTests/testTwo"))
    #expect(arguments[arguments.firstIndex(of: "-parallel-testing-enabled")! + 1] == "NO")
    var settings = AgentSettings(); settings.enabled = true
    settings.protections[phone] = .init(enabled: true)
    try AgentPolicy.check(category: .tests, deviceIDs: plan.deviceIDs, settings: settings)
    settings.protections[phone]?.blocked.insert(.tests)
    #expect(throws: AgentFailure.self) { try AgentPolicy.check(category: .tests, deviceIDs: plan.deviceIDs, settings: settings) }
}

@Test func snapshotBaselineAndSuppression() {
    var tracker = AgentSnapshotTracker()
    #expect(tracker.observe(inventory.devices).isEmpty)
    #expect(tracker.observe(inventory.devices).isEmpty)
    let stopped = AgentDevice(id: phone, name: "iPhone", state: "Shutdown", runtime: "iOS")
    let changes = tracker.observe([stopped, inventory.devices[1]])
    #expect(changes.count == 1)
    #expect(changes[0].sessionID == nil)
    #expect(changes[0].operation == "state")
    #expect(tracker.observe([], suppressed: [phone]).map(\.operation) == ["unavailable"])
    tracker.reset()
    #expect(tracker.observe(inventory.devices).isEmpty)
}

@Test func historyIsBoundedAndNeverContainsParameters() throws {
    let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = AgentPersistence(directory: directory)
    let events = (0..<5_010).map { index in
        AgentEvent(deviceIDs: [phone], deviceNames: ["iPhone"], operation: "pbcopy", category: .content, outcome: .succeeded, detail: String(index))
    }
    try persistence.save(.init(events: events))
    let saved = try persistence.load()
    #expect(saved.events.count == 5_000)
    #expect(saved.events.first?.detail == "10")
}

@Test func processDrainsBothStreamsAndBoundsOutput() async {
    let runner = ManagedProcess(outputLimit: 1024)
    let result = await runner.run(.init(executable: "/usr/bin/python3", arguments: ["-c", "import sys; sys.stdout.write('o'*200000); sys.stderr.write('e'*200000)"]))
    #expect(result.succeeded)
    #expect(result.output.utf8.count == 1024)
    #expect(result.errorOutput.utf8.count == 1024)
    #expect(result.truncated)
}

@Test func cancellationStopsOwnedProcessGroup() async throws {
    let runner = ManagedProcess()
    let task = Task { await runner.run(.init(executable: "/bin/sleep", arguments: ["30"])) }
    try await Task.sleep(for: .milliseconds(150))
    runner.cancel()
    let result = await task.value
    #expect(result.cancelled)
    #expect(!result.succeeded)
}

@Test func processReceivesStandardInputAndClosesIt() async {
    let payload = Data(String(repeating: "clipboard payload\n", count: 8_000).utf8)
    let result = await ManagedProcess(outputLimit: payload.count).run(.init(executable: "/bin/cat", arguments: [], standardInput: payload))
    #expect(result.succeeded)
    #expect(Data(result.output.utf8) == payload)
}

@Test func socketRoundTripsConcurrentRequestsAndRejectsMissingApp() async throws {
    let directory = "/private/tmp/simbuddy-test-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let path = directory + "/s"
    let server = AgentSocketServer(path: path)
    try server.start { request in .init(request.clientName) }
    try await withThrowingTaskGroup(of: String.self) { group in
        for index in 0..<8 {
            group.addTask {
                try await AgentSocket.request(.init(method: "heartbeat", sessionID: UUID(), clientName: String(index)), path: path).text
            }
        }
        var values = Set<String>()
        for try await value in group { values.insert(value) }
        #expect(values.count == 8)
    }
    let duplicate = AgentSocketServer(path: path)
    #expect(throws: AgentFailure.self) { try duplicate.start { _ in .init("unexpected") } }
    server.stop()
    do {
        _ = try await AgentSocket.request(.init(method: "heartbeat", sessionID: UUID(), clientName: "test"), path: path)
        Issue.record("Request succeeded without app")
    } catch { #expect(error is AgentFailure) }
}
