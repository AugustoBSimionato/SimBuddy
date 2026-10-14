import AgentCore
import AVFoundation
import Foundation
import Testing

private let deviceID = "11111111-1111-1111-1111-111111111111"
private let snapshot = Data("""
{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-0":[{"udid":"\(deviceID)","name":"Test phone","state":"Booted","isAvailable":true}]},"pairs":{}}
""".utf8)

private final class ControlledRunner: AgentProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var finished = false
    private var continuations: [CheckedContinuation<AgentProcessResult, Never>] = []
    private(set) var calls = 0

    func run(_ command: AgentCommand) async -> AgentProcessResult {
        await withCheckedContinuation { continuation in
            lock.withLock {
                calls += 1
                if cancelled { continuation.resume(returning: .init(exitCode: -1, cancelled: true)) }
                else if finished { continuation.resume(returning: .init(exitCode: 0)) }
                else { continuations.append(continuation) }
            }
        }
    }
    func finish() {
        let pending = lock.withLock { finished = true; let value = continuations; continuations = []; return value }
        for continuation in pending { continuation.resume(returning: .init(exitCode: 0, output: "private output")) }
    }
    func cancel() {
        let pending = lock.withLock { cancelled = true; let value = continuations; continuations = []; return value }
        for continuation in pending { continuation.resume(returning: .init(exitCode: -1, cancelled: true)) }
    }
}

@MainActor
private final class MonitorFixture {
    let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
    let runner = ControlledRunner()
    let monitor: AgentMonitor
    let sessionID = UUID()

    init(protected: Bool = false) throws {
        let persistence = AgentPersistence(directory: directory)
        var settings = AgentSettings(); settings.enabled = true
        settings.protections[deviceID] = .init(enabled: protected)
        try persistence.save(.init(settings: settings))
        monitor = AgentMonitor(persistence: persistence, notificationsEnabled: false, runnerFactory: { [runner] _ in runner }, refresh: { true })
        monitor.receiveSnapshot(snapshot)
    }
    func submit(_ operation: String, sessionID: UUID? = nil, devices: [String] = [deviceID]) async -> AgentBridgeResponse {
        await monitor.handle(.init(method: "execute_operation", sessionID: sessionID ?? self.sessionID, clientName: "test", input: .init(operation: operation, devices: devices)))
    }
    func waitFor(_ outcome: AgentOutcome, operationID: UUID? = nil) async throws {
        for _ in 0..<100 {
            if monitor.events.contains(where: { $0.outcome == outcome && (operationID == nil || $0.operationID == operationID) }) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for \(outcome)")
    }
    func cleanup() {
        monitor.shutdown()
        try? FileManager.default.removeItem(at: directory)
    }
}

@Test @MainActor func blockedOperationNeverStartsProcess() async throws {
    let fixture = try MonitorFixture(protected: true)
    defer { fixture.cleanup() }
    let response = await fixture.submit("shutdown")
    #expect(response.isError)
    #expect(fixture.runner.calls == 0)
    #expect(fixture.monitor.events.map(\.outcome) == [.requested, .blocked])
    #expect(fixture.monitor.activeOperations.isEmpty)
}

@Test @MainActor func queuedOperationRechecksRulesAndSerializesTargets() async throws {
    let fixture = try MonitorFixture()
    defer { fixture.cleanup() }
    let first = await fixture.submit("boot")
    #expect(!first.isError)
    try await fixture.waitFor(.started)
    let firstID = try #require(fixture.monitor.events.last?.operationID)
    #expect(fixture.monitor.activeOperations.map(\.id) == [firstID])
    #expect(fixture.monitor.activeOperations.first?.event.outcome == .started)
    #expect(fixture.monitor.activeOperations.first?.event.deviceNames == ["Test phone"])
    let second = await fixture.submit("shutdown", sessionID: UUID())
    #expect(!second.isError)
    let secondID = fixture.monitor.events.last!.operationID!
    #expect(fixture.monitor.activeOperations.map(\.id) == [firstID, secondID])
    #expect(fixture.monitor.activeOperations.last?.event.outcome == .queued)
    #expect(fixture.runner.calls == 1)
    fixture.monitor.setProtection(.init(enabled: true), for: deviceID)
    try await fixture.waitFor(.blocked, operationID: secondID)
    #expect(fixture.monitor.activeOperations.map(\.id) == [firstID])
    #expect(fixture.runner.calls == 1)
    fixture.runner.finish()
    try await fixture.waitFor(.succeeded)
    #expect(fixture.monitor.activeOperations.isEmpty)
    #expect(fixture.monitor.events.allSatisfy { $0.detail != "private output" })
}

@Test @MainActor func disablingModePreservesRunningOperationAndRejectsNewOnes() async throws {
    let fixture = try MonitorFixture()
    defer { fixture.cleanup() }
    _ = await fixture.submit("boot")
    try await fixture.waitFor(.started)
    fixture.monitor.setEnabled(false)
    #expect(fixture.monitor.activeOperations.count == 1)
    #expect(fixture.monitor.activeOperations.first?.event.outcome == .started)
    #expect(await fixture.submit("boot").isError)
    fixture.runner.finish()
    try await fixture.waitFor(.succeeded)
}

@Test @MainActor func cancellationRequiresOwningSession() async throws {
    let fixture = try MonitorFixture()
    defer { fixture.cleanup() }
    _ = await fixture.submit("boot")
    try await fixture.waitFor(.started)
    let id = fixture.monitor.events.last!.operationID!
    let foreign = await fixture.monitor.handle(.init(method: "cancel_operation", sessionID: UUID(), clientName: "other", operationID: id))
    #expect(foreign.isError)
    let own = await fixture.monitor.handle(.init(method: "cancel_operation", sessionID: fixture.sessionID, clientName: "test", operationID: id))
    #expect(!own.isError)
    try await fixture.waitFor(.cancelled)
    #expect(fixture.monitor.activeOperations.isEmpty)
}

@Test @MainActor func shutdownPersistsInterruptedOperations() async throws {
    let fixture = try MonitorFixture()
    defer { fixture.cleanup() }
    _ = await fixture.submit("boot")
    try await fixture.waitFor(.started)
    fixture.monitor.shutdown()
    #expect(fixture.monitor.activeOperations.isEmpty)
    let saved = try AgentPersistence(directory: fixture.directory).load()
    #expect(saved.events.last?.outcome == .interrupted)
    #expect(saved.events.last?.detail == nil)
}

@Test @MainActor func clipboardWriteRequiresSuccessfulReadback() async throws {
    let fixture = try MonitorFixture()
    defer { fixture.cleanup() }
    let response = await fixture.monitor.handle(.init(method: "execute_operation", sessionID: fixture.sessionID,
        clientName: "test", input: .init(operation: "pbcopy", devices: [deviceID], parameters: ["text": "private payload"])))
    #expect(!response.isError)
    try await fixture.waitFor(.started)
    fixture.runner.finish()
    try await fixture.waitFor(.failed)
    #expect(fixture.monitor.activeOperations.isEmpty)
    #expect(fixture.monitor.events.last?.detail == "clipboardVerification")
    #expect(fixture.monitor.events.allSatisfy { $0.detail?.contains("private payload") != true })
}

@Test @MainActor func managedSnapshotDoesNotDuplicateAgentEvents() async throws {
    let fixture = try MonitorFixture()
    defer { fixture.cleanup() }
    _ = await fixture.submit("shutdown")
    try await fixture.waitFor(.started)
    fixture.monitor.receiveSnapshot(Data(String(decoding: snapshot, as: UTF8.self).replacing("Booted", with: "Shutdown").utf8))
    #expect(!fixture.monitor.events.contains { $0.outcome == .observed })
    fixture.runner.finish()
    try await fixture.waitFor(.succeeded)
}

@Test @MainActor func failedSnapshotPreservesBaselineAndDeviceInventory() throws {
    let fixture = try MonitorFixture()
    defer { fixture.cleanup() }
    #expect(!fixture.monitor.receiveSnapshot(Data("unavailable".utf8)))
    #expect(fixture.monitor.inventory.devices.count == 1)
    #expect(fixture.monitor.events.isEmpty)
    #expect(fixture.monitor.receiveSnapshot(snapshot))
    #expect(fixture.monitor.events.isEmpty)
}

@Test @MainActor func activeOperationsKeepAdmissionOrderWhileDifferentDevicesRunConcurrently() async throws {
    let fixture = try MonitorFixture()
    defer { fixture.cleanup() }
    let otherDeviceID = "22222222-2222-2222-2222-222222222222"
    let secondDevice = String(decoding: snapshot, as: UTF8.self)
        .replacingOccurrences(of: deviceID, with: otherDeviceID)
        .replacingOccurrences(of: "Test phone", with: "Other phone")
    var inventory = try #require(JSONSerialization.jsonObject(with: snapshot) as? [String: Any])
    let otherInventory = try #require(JSONSerialization.jsonObject(with: Data(secondDevice.utf8)) as? [String: Any])
    var devices = try #require(inventory["devices"] as? [String: [[String: Any]]])
    let otherDevices = try #require(otherInventory["devices"] as? [String: [[String: Any]]])
    let runtime = "com.apple.CoreSimulator.SimRuntime.iOS-26-0"
    devices[runtime, default: []] += otherDevices[runtime, default: []]
    inventory["devices"] = devices
    fixture.monitor.receiveSnapshot(try JSONSerialization.data(withJSONObject: inventory))

    #expect(await !fixture.submit("boot").isError)
    let firstID = try #require(fixture.monitor.activeOperations.first?.id)
    try await fixture.waitFor(.started, operationID: firstID)
    #expect(await !fixture.submit("boot", devices: [otherDeviceID]).isError)
    let secondID = try #require(fixture.monitor.activeOperations.last?.id)
    try await fixture.waitFor(.started, operationID: secondID)
    #expect(fixture.runner.calls == 2)
    #expect(fixture.monitor.activeOperations.map(\.id) == [firstID, secondID])
    #expect(fixture.monitor.activeOperations.map(\.event.deviceNames) == [["Test phone"], ["Other phone"]])

    fixture.runner.finish()
    try await fixture.waitFor(.succeeded, operationID: firstID)
    try await fixture.waitFor(.succeeded, operationID: secondID)
    #expect(fixture.monitor.activeOperations.isEmpty)

    #expect(await !fixture.submit("shutdown", devices: ["all"]).isError)
    let batchID = try #require(fixture.monitor.activeOperations.first?.id)
    #expect(fixture.monitor.activeOperations.first?.event.deviceNames == ["Test phone", "Other phone"])
    try await fixture.waitFor(.succeeded, operationID: batchID)
    #expect(fixture.monitor.activeOperations.isEmpty)
}

@Test @MainActor func cancellingQueuedOperationLeavesRunningOperationVisible() async throws {
    let fixture = try MonitorFixture()
    defer { fixture.cleanup() }
    _ = await fixture.submit("boot")
    try await fixture.waitFor(.started)
    let firstID = try #require(fixture.monitor.activeOperations.first?.id)
    _ = await fixture.submit("shutdown")
    let secondID = try #require(fixture.monitor.activeOperations.last?.id)
    #expect(fixture.monitor.activeOperations.last?.event.outcome == .queued)

    let response = await fixture.monitor.handle(.init(method: "cancel_operation", sessionID: fixture.sessionID,
        clientName: "test", operationID: secondID))
    #expect(!response.isError)
    #expect(fixture.monitor.activeOperations.map(\.id) == [firstID])
    #expect(fixture.runner.calls == 1)
    fixture.runner.finish()
    try await fixture.waitFor(.succeeded, operationID: firstID)
    #expect(fixture.monitor.activeOperations.isEmpty)
}

@Test @MainActor func activeOperationsDoNotRestoreUnfinishedHistory() throws {
    let fixture = try MonitorFixture()
    defer { fixture.cleanup() }
    let persistence = AgentPersistence(directory: fixture.directory)
    try persistence.save(.init(settings: fixture.monitor.settings, events: [
        AgentEvent(operationID: UUID(), deviceIDs: [deviceID], deviceNames: ["Test phone"], operation: "boot", category: .boot, outcome: .started)
    ]))
    let restored = AgentMonitor(persistence: persistence, notificationsEnabled: false)
    #expect(restored.activeOperations.isEmpty)
    #expect(restored.events.last?.outcome == .interrupted)
}

@Test @MainActor func connectionsWithSameClientNameRemainDistinctWhenMonitoringIsDisabled() async throws {
    let fixture = try MonitorFixture()
    defer { fixture.cleanup() }
    fixture.monitor.setEnabled(false)
    let otherSession = UUID()
    for sessionID in [fixture.sessionID, otherSession] {
        #expect(await !fixture.monitor.handle(.init(method: "heartbeat", sessionID: sessionID, clientName: "test")).isError)
    }
    #expect(fixture.monitor.sessions.map(\.id) == [fixture.sessionID, otherSession])
    #expect(fixture.monitor.sessions.map(\.clientName) == ["test", "test"])
    _ = await fixture.monitor.handle(.init(method: "disconnect", sessionID: fixture.sessionID, clientName: "test"))
    #expect(fixture.monitor.sessions.map(\.id) == [otherSession])
}

@Test @MainActor func everyCatalogOperationHasAHumanReadableTitle() {
    for definition in OperationCatalog.definitions {
        let event = AgentEvent(deviceIDs: [], deviceNames: [], operation: definition.name, category: definition.category, outcome: .queued)
        #expect(event.operationTitle != definition.name)
    }
}

@Test @MainActor func notificationsGroupBySimulatorAndSessionAndDeliverBlocksImmediately() async throws {
    var deliveries: [[AgentEvent]] = []
    let notifications = AgentNotifications(batchDelay: .milliseconds(30)) { deliveries.append($0) }
    let session = UUID()
    func event(_ outcome: AgentOutcome, sessionID: UUID = session) -> AgentEvent {
        AgentEvent(sessionID: sessionID, deviceIDs: [deviceID], deviceNames: ["Test phone"], operation: "boot", category: .boot, outcome: outcome)
    }
    notifications.enqueue(event(.requested))
    notifications.enqueue(event(.started))
    notifications.enqueue(event(.succeeded))
    notifications.enqueue(event(.succeeded, sessionID: UUID()))
    notifications.enqueue(event(.blocked))
    #expect(deliveries.count == 1)
    #expect(deliveries[0][0].outcome == .blocked)
    try await Task.sleep(for: .milliseconds(80))
    #expect(deliveries.count == 3)
    #expect(deliveries.map(\.count).sorted() == [1, 1, 2])
    notifications.enqueue(event(.started))
    notifications.cancelPending()
    try await Task.sleep(for: .milliseconds(50))
    #expect(deliveries.count == 3)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SIMBUDDY_SMOKE_TESTS"] == "1"), .timeLimit(.minutes(10)))
@MainActor func disposableSimulatorSmokeTest() async throws {
    let directory = URL.temporaryDirectory.appending(path: "SimBuddySmoke-\(UUID().uuidString)")
    let persistence = AgentPersistence(directory: directory)
    var settings = AgentSettings(); settings.enabled = true
    try persistence.save(.init(settings: settings))
    weak var liveMonitor: AgentMonitor?
    let monitor = AgentMonitor(persistence: persistence, notificationsEnabled: false, refresh: {
        let result = await ManagedProcess(outputLimit: 2_097_152).run(.init(arguments: ["simctl", "list", "--json"]))
        guard result.succeeded else { return false }
        let data = Data(result.output.utf8)
        guard (try? AgentInventory.decode(data)) != nil else { return false }
        liveMonitor?.receiveSnapshot(data)
        return true
    })
    liveMonitor = monitor
    let session = UUID()
    var disposableID: String?

    struct Status: Decodable { let outcome: AgentOutcome; let results: [AgentProcessResult] }
    func status(_ id: UUID) async throws -> Status {
        let response = await monitor.handle(.init(method: "get_operation", sessionID: session, clientName: "Smoke test", operationID: id))
        if response.isError { throw AgentFailure(response.text) }
        return try JSONDecoder().decode(Status.self, from: Data(response.text.utf8))
    }
    func submit(_ input: AgentOperationInput, wait: Bool = true, allowedOutcomes: Set<AgentOutcome> = [.succeeded]) async throws -> (UUID, Status?) {
        let response = await monitor.handle(.init(method: input.operation == "test" ? "run_tests" : "execute_operation", sessionID: session, clientName: "Smoke test", input: input))
        if response.isError { throw AgentFailure(response.text) }
        let admission = try JSONDecoder().decode([String: String].self, from: Data(response.text.utf8))
        guard let raw = admission["operationID"], let id = UUID(uuidString: raw) else { throw AgentFailure("Missing operation ID.") }
        if !wait { return (id, nil) }
        for _ in 0..<2_400 {
            let current = try await status(id)
            if current.outcome.isTerminal {
                guard allowedOutcomes.contains(current.outcome) else { throw AgentFailure("Smoke operation \(input.operation) failed: \(current.results)") }
                return (id, current)
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw AgentFailure("Smoke operation timed out: \(input.operation)")
    }
    do {
        let (_, created) = try await submit(.init(operation: "create", parameters: [
            "name": "SimBuddy Smoke \(UUID().uuidString.prefix(8))",
            "deviceType": "com.apple.CoreSimulator.SimDeviceType.iPhone-16",
            "runtime": "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
        ]))
        let id = created!.results[0].output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: id) != nil else { throw AgentFailure("Invalid disposable simulator ID.") }
        disposableID = id
        _ = try await submit(.init(operation: "boot", devices: [id]))
        monitor.setProtection(.init(enabled: true), for: id)
        let denied = await monitor.handle(.init(method: "execute_operation", sessionID: session, clientName: "Smoke test", input: .init(operation: "shutdown", devices: [id])))
        #expect(denied.isError)
        #expect(monitor.inventory.devices.first { $0.id == id }?.state == "Booted")
        _ = try await submit(.init(operation: "ui.appearance.set", devices: [id], parameters: ["value": "dark"]))
        let screenshot = directory.appending(path: "capture.png")
        _ = try await submit(.init(operation: "screenshot", devices: [id], parameters: ["path": screenshot.path]))
        #expect(FileManager.default.fileExists(atPath: screenshot.path))
        let video = directory.appending(path: "recording.mov")
        let (recordingID, _) = try await submit(.init(operation: "recordVideo", devices: [id], parameters: ["path": video.path]), wait: false)
        try await Task.sleep(for: .seconds(2))
        let cancellation = await monitor.handle(.init(method: "cancel_operation", sessionID: session, clientName: "Smoke test", operationID: recordingID))
        #expect(!cancellation.isError)
        for _ in 0..<100 {
            if try await status(recordingID).outcome.isTerminal { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(try await status(recordingID).outcome == .cancelled)
        #expect((try? video.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 > 0)
        let duration = try await AVURLAsset(url: video).load(.duration)
        #expect(duration.seconds.isFinite && duration.seconds > 0)
        let (_, copy) = try await submit(.init(operation: "pbcopy", devices: [id], parameters: ["text": "smoke-private-clipboard"]), allowedOutcomes: [.succeeded, .failed])
        if copy?.outcome == .succeeded {
            let (_, clipboard) = try await submit(.init(operation: "pbpaste", devices: [id]))
            #expect(clipboard?.results.first?.output.contains("smoke-private-clipboard") == true)
        } else {
            #expect(copy?.results.last?.errorOutput.contains("did not retain the text") == true)
        }
        if let project = ProcessInfo.processInfo.environment["SIMBUDDY_SMOKE_PROJECT"] {
            _ = try await submit(.init(operation: "test", devices: [id], parameters: ["projectPath": project, "scheme": "Smoke"]))
        }
        #expect(!monitor.events.contains { $0.detail?.contains("smoke-private-clipboard") == true })
        monitor.setProtection(.init(enabled: false), for: id)
        _ = try await submit(.init(operation: "shutdown", devices: [id]))
        _ = try await submit(.init(operation: "delete", devices: [id]))
        disposableID = nil
    } catch {
        monitor.shutdown()
        if let id = disposableID {
            _ = await ManagedProcess().run(.init(arguments: ["simctl", "shutdown", id]))
            _ = await ManagedProcess().run(.init(arguments: ["simctl", "delete", id]))
        }
        try? FileManager.default.removeItem(at: directory)
        throw error
    }
    monitor.shutdown()
    try? FileManager.default.removeItem(at: directory)
}
