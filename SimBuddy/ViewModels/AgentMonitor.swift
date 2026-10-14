import AgentCore
import Foundation
import Observation
import UserNotifications

@Observable
@MainActor
final class AgentMonitor {
    struct Session: Equatable, Identifiable {
        let id: UUID
        let clientName: String
        var lastSeen: Date
    }

    private(set) var settings: AgentSettings
    private(set) var events: [AgentEvent]
    private(set) var sessions: [Session] = []
    private(set) var bridgeError: String?
    private(set) var persistenceError: String?
    private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var inventory = AgentInventory(devices: [])
    var presentedEvent: AgentEvent?

    @ObservationIgnored private let persistence: AgentPersistence
    @ObservationIgnored private let notifications = AgentNotifications()
    @ObservationIgnored private let server = AgentSocketServer()
    @ObservationIgnored private var tracker = AgentSnapshotTracker()
    @ObservationIgnored private var jobs: [UUID: Job] = [:]
    @ObservationIgnored private var activeDevices: Set<String> = []
    @ObservationIgnored private var managedStateDevices: Set<String> = []
    @ObservationIgnored private var internalOperations: [UUID: Set<String>] = [:]
    @ObservationIgnored private var observedAt: Date?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var refreshInventory: (() async -> Bool)?
    @ObservationIgnored private var terminating = false
    @ObservationIgnored private let runnerFactory: (Int) -> any AgentProcessRunning
    @ObservationIgnored private let notificationsEnabled: Bool

    private final class Job {
        let id: UUID
        let request: AgentBridgeRequest
        let input: AgentOperationInput
        var plan: AgentExecutionPlan
        var completedAt: Date?
        var outcome: AgentOutcome = .queued {
            didSet { if outcome.isTerminal { completedAt = Date() } }
        }
        var results: [AgentProcessResult] = []
        var runner: (any AgentProcessRunning)?
        var task: Task<Void, Never>?
        init(id: UUID, request: AgentBridgeRequest, input: AgentOperationInput, plan: AgentExecutionPlan) {
            self.id = id; self.request = request; self.input = input; self.plan = plan
        }
    }

    init(persistence: AgentPersistence = AgentPersistence(), notificationsEnabled: Bool = true,
         runnerFactory: @escaping (Int) -> any AgentProcessRunning = { ManagedProcess(outputLimit: $0) },
         refresh: (() async -> Bool)? = nil) {
        self.persistence = persistence
        self.notificationsEnabled = notificationsEnabled
        self.runnerFactory = runnerFactory
        self.refreshInventory = refresh
        do {
            let saved = try persistence.load()
            settings = saved.settings; events = saved.events
            let unfinished = Dictionary(grouping: events.filter { $0.operationID != nil }, by: { $0.operationID! })
            for group in unfinished.values {
                if let last = group.last, !last.outcome.isTerminal {
                    events.append(AgentEvent(operationID: last.operationID, sessionID: last.sessionID,
                        clientName: last.clientName, deviceIDs: last.deviceIDs, deviceNames: last.deviceNames,
                        operation: last.operation, category: last.category, outcome: .interrupted))
                }
            }
            events = Array(events.suffix(5_000))
        } catch {
            settings = AgentSettings(); events = []
            persistenceError = String(localized: "Não foi possível carregar as regras de agentes. A integração está desativada.")
        }
    }

    var enabled: Bool { settings.enabled }
    var protectedCount: Int { inventory.devices.filter { protection(for: $0.id).enabled }.count }

    func start(refresh: @escaping () async -> Bool, openEvent: @escaping (UUID) -> Void) {
        refreshInventory = refresh
        notifications.openEvent = openEvent
        notifications.authorizationChanged = { [weak self] in self?.notificationStatus = $0 }
        notifications.start()
        do { try server.start { [weak self] request in
            guard let self else { return .init("SimBuddy is unavailable.", isError: true) }
            return await self.handle(request)
        } } catch { bridgeError = error.localizedDescription }
    }

    func setEnabled(_ enabled: Bool) {
        settings.enabled = enabled
        tracker.reset()
        notifications.cancelPending()
        persistNow()
        if enabled && notificationsEnabled {
            Task { await notifications.requestAuthorization(); _ = await refreshInventory?() }
        }
    }

    func protection(for id: String) -> AgentProtection { settings.protections[id] ?? .init() }
    func setProtection(_ value: AgentProtection, for id: String) {
        settings.protections[id] = value
        persistNow()
    }
    func setNotifications(_ enabled: Bool, category: AgentCategory) {
        if enabled { settings.mutedCategories.remove(category) } else { settings.mutedCategories.insert(category) }
        persistNow()
    }

    func refreshNotificationAuthorization() { Task { await notifications.updateAuthorization() } }
    func expireSessions() { sessions.removeAll { Date().timeIntervalSince($0.lastSeen) > 30 } }

    @discardableResult
    func receiveSnapshot(_ data: Data) -> Bool {
        guard let snapshot = try? AgentInventory.decode(data) else { return false }
        inventory = snapshot
        observedAt = Date()
        let suppressed = managedStateDevices.union(internalOperations.values.reduce(into: Set<String>()) { $0.formUnion($1) })
        if enabled { tracker.observe(snapshot.devices, suppressed: suppressed).forEach(record) }
        else { tracker.reset() }
        expireSessions()
        return true
    }

    func beginInternalOperation(_ ids: Set<String>) -> UUID {
        let id = UUID(); internalOperations[id] = ids; return id
    }
    func endInternalOperation(_ id: UUID) { internalOperations[id] = nil }

    func openEvent(_ id: UUID) { presentedEvent = events.first { $0.id == id } }

    func shutdown() {
        terminating = true
        server.stop()
        for job in jobs.values where !job.outcome.isTerminal {
            job.outcome = .interrupted
            record(event(for: job, outcome: .interrupted))
            job.runner?.cancel(); job.task?.cancel()
        }
        notifications.cancelPending()
        persistNow()
    }

    private func record(_ event: AgentEvent) {
        events.append(event)
        if events.count > 5_000 { events.removeFirst(events.count - 5_000) }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
        if notificationsEnabled && enabled && !terminating && !settings.mutedCategories.contains(event.category) { notifications.enqueue(event) }
    }

    private func persistNow() {
        saveTask?.cancel(); saveTask = nil
        do { try persistence.save(.init(settings: settings, events: events)); persistenceError = nil }
        catch { persistenceError = String(localized: "Não foi possível salvar as regras ou o histórico de agentes.") }
    }

    private func event(for job: Job, outcome: AgentOutcome, detail: String? = nil) -> AgentEvent {
        AgentEvent(operationID: job.id, sessionID: job.request.sessionID, clientName: job.request.clientName,
                   deviceIDs: job.plan.deviceIDs,
                   deviceNames: job.plan.deviceIDs.map { id in inventory.devices.first { $0.id == id }?.name ?? id },
                   operation: job.plan.operation, category: job.plan.category, outcome: outcome, detail: detail)
    }

    func handle(_ request: AgentBridgeRequest) async -> AgentBridgeResponse {
        do {
            guard !terminating, request.clientName.count <= 120 else { throw AgentFailure("Bridge is unavailable or client name is invalid.") }
            if request.method == "disconnect" {
                sessions.removeAll { $0.id == request.sessionID }; return .init("Disconnected.")
            }
            if let index = sessions.firstIndex(where: { $0.id == request.sessionID }) { sessions[index].lastSeen = Date() }
            else {
                guard sessions.count < 32 else { throw AgentFailure("Too many MCP sessions.") }
                sessions.append(.init(id: request.sessionID, clientName: request.clientName, lastSeen: Date()))
            }
            if request.method == "heartbeat" { return .init(enabled ? "Monitoring enabled." : "Monitoring disabled.") }
            if ["get_operation", "cancel_operation"].contains(request.method) {
                guard let id = request.operationID, let job = jobs[id], job.request.sessionID == request.sessionID else { throw AgentFailure("Unknown operation in this session.") }
                if request.method == "cancel_operation", !job.outcome.isTerminal {
                    job.runner?.cancel(); job.task?.cancel()
                    if job.outcome == .queued { job.outcome = .cancelled; record(event(for: job, outcome: .cancelled)) }
                }
                struct Status: Encodable {
                    let operationID: UUID; let outcome: AgentOutcome; let results: [AgentProcessResult]; let resultBundlePath: String?
                }
                return try .encoded(Status(operationID: id, outcome: job.outcome, results: job.results, resultBundlePath: job.plan.resultBundlePath))
            }
            guard enabled else { throw AgentFailure("Enable agent monitoring in SimBuddy before using tools.") }
            if request.method == "describe_operations" {
                record(AgentEvent(sessionID: request.sessionID, clientName: request.clientName, deviceIDs: [], deviceNames: [], operation: request.method, category: .inspection, outcome: .succeeded))
                return try .encoded(OperationCatalog.definitions)
            }
            guard ["list_simulators", "execute_operation", "run_tests"].contains(request.method) else { throw AgentFailure("Unknown bridge method.") }
            guard await refreshInventory?() == true else { throw AgentFailure("Simulator inventory is unavailable. No operation was executed.") }
            guard enabled else { throw AgentFailure("Agent monitoring was disabled.") }
            if request.method == "list_simulators" {
                struct Device: Encodable { let simulator: AgentDevice; let protection: AgentProtection }
                do { try AgentPolicy.check(category: .inspection, deviceIDs: inventory.devices.map(\.id), settings: settings) }
                catch {
                    record(AgentEvent(sessionID: request.sessionID, clientName: request.clientName, deviceIDs: inventory.devices.map(\.id),
                        deviceNames: inventory.devices.map(\.name), operation: request.method, category: .inspection, outcome: .blocked, detail: "protectedDevice"))
                    throw error
                }
                record(AgentEvent(sessionID: request.sessionID, clientName: request.clientName, deviceIDs: [], deviceNames: [], operation: request.method, category: .inspection, outcome: .succeeded))
                return try .encoded(inventory.devices.map { Device(simulator: $0, protection: protection(for: $0.id)) })
            }
            guard let input = request.input, (request.method == "run_tests") == (input.operation == "test") else { throw AgentFailure("Invalid operation input or tool.") }
            guard jobs.values.filter({ !$0.outcome.isTerminal }).count < 32 else { throw AgentFailure("Operation queue is full.") }
            let id = UUID()
            let resultPath = persistence.directory.appending(path: "Results/\(id.uuidString).xcresult").path
            let plan: AgentExecutionPlan
            do { plan = try OperationCatalog.plan(input, inventory: inventory, resultBundlePath: resultPath) }
            catch {
                let definition = OperationCatalog.definitions.first { $0.name == input.operation }
                let ids = input.devices.filter { id in inventory.devices.contains { $0.id == id } }
                record(AgentEvent(operationID: id, sessionID: request.sessionID, clientName: request.clientName,
                    deviceIDs: ids, deviceNames: ids, operation: definition?.name ?? "unsupported",
                    category: definition?.category ?? .inspection, outcome: .blocked, detail: "invalidInput"))
                throw error
            }
            var frozen = input
            if !["create", "pair", "unpair", "pair_activate"].contains(input.operation) {
                frozen.devices = plan.commands.compactMap { command in
                    command.arguments.first { argument in inventory.devices.contains { $0.id == argument } }
                }
                if input.operation == "test" { frozen.devices = input.devices.flatMap { target in target == "booted" ? inventory.devices.filter { $0.state == "Booted" }.map(\.id) : target == "all" ? inventory.devices.map(\.id) : [target] } }
            }
            let job = Job(id: id, request: request, input: frozen, plan: plan)
            record(event(for: job, outcome: .requested))
            do { try AgentPolicy.check(category: plan.category, deviceIDs: plan.deviceIDs, settings: settings) }
            catch { record(event(for: job, outcome: .blocked, detail: plan.category.rawValue)); throw error }
            jobs[id] = job
            record(event(for: job, outcome: .queued))
            job.task = Task { await execute(job) }
            pruneCompletedOperations()
            return try .encoded(["operationID": id.uuidString, "status": "queued"])
        } catch { return .init(error.localizedDescription, isError: true) }
    }

    private func pruneCompletedOperations() {
        let completed = jobs.values.filter { $0.outcome.isTerminal }.sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
        for old in completed.prefix(max(0, completed.count - 100)) { jobs[old.id] = nil }
    }

    private func execute(_ job: Job) async {
        var reserved: Set<String> = []
        defer {
            activeDevices.subtract(reserved); managedStateDevices.subtract(reserved)
            job.runner = nil; job.task = nil
            pruneCompletedOperations()
        }
        do {
            while !Task.isCancelled {
                if observedAt == nil || Date().timeIntervalSince(observedAt!) > 3 {
                    guard await refreshInventory?() == true else { throw AgentFailure("Simulator inventory unavailable.", code: .unavailable) }
                }
                let plan = try OperationCatalog.plan(job.input, inventory: inventory, resultBundlePath: job.plan.resultBundlePath)
                try AgentPolicy.check(category: plan.category, deviceIDs: plan.deviceIDs, settings: settings)
                if activeDevices.isDisjoint(with: plan.deviceIDs) {
                    job.plan = plan; reserved = Set(plan.deviceIDs); activeDevices.formUnion(reserved)
                    if ["boot", "shutdown", "reboot", "erase", "delete", "create", "clone", "test", "pair", "unpair", "pair_activate"].contains(plan.operation) {
                        managedStateDevices.formUnion(reserved)
                    }
                    break
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            try Task.checkCancellation()
            job.outcome = .started
            record(event(for: job, outcome: .started))
            if job.plan.resultBundlePath != nil {
                try FileManager.default.createDirectory(at: persistence.directory.appending(path: "Results"), withIntermediateDirectories: true)
            }
            for command in job.plan.commands {
                try Task.checkCancellation()
                var currentSettings = settings
                currentSettings.enabled = true
                try AgentPolicy.check(category: job.plan.category, deviceIDs: job.plan.deviceIDs, settings: currentSettings)
                let runner = runnerFactory(32_768 / max(1, job.plan.commands.count)); job.runner = runner
                let result = await runner.run(command)
                guard !terminating else { return }
                job.results.append(result)
                if result.cancelled { throw CancellationError() }
                guard result.succeeded else {
                    job.outcome = .failed
                    record(event(for: job, outcome: .failed, detail: String(result.exitCode)))
                    _ = await refreshInventory?()
                    return
                }
                if job.plan.operation == "pbcopy", let target = command.arguments.last, let input = command.standardInput {
                    let verifier = runnerFactory(max(32_768, input.count + 1)); job.runner = verifier
                    let verification = await verifier.run(.init(arguments: ["simctl", "pbpaste", target]))
                    guard !terminating else { return }
                    if verification.cancelled { throw CancellationError() }
                    if !verification.succeeded || Data(verification.output.utf8) != input {
                        job.results.append(.init(exitCode: -1, errorOutput: "simctl pbcopy did not retain the text. This Xcode runtime may have a pasteboard limitation."))
                        job.outcome = .failed
                        record(event(for: job, outcome: .failed, detail: "clipboardVerification"))
                        return
                    }
                }
            }
            if ["create", "clone"].contains(job.plan.operation) {
                for id in job.results.flatMap({ $0.output.split(whereSeparator: \.isWhitespace).map(String.init) }) where UUID(uuidString: id) != nil {
                    reserved.insert(id); activeDevices.insert(id); managedStateDevices.insert(id)
                }
            }
            _ = await refreshInventory?()
            guard !terminating else { return }
            job.outcome = .succeeded
            record(event(for: job, outcome: .succeeded))
        } catch {
            guard !terminating, job.outcome != .cancelled else { return }
            let code = (error as? AgentFailure)?.code
            job.outcome = error is CancellationError ? .cancelled : code == .protectedDevice || code == .disabled ? .blocked : .failed
            record(event(for: job, outcome: job.outcome, detail: code?.rawValue))
            _ = await refreshInventory?()
        }
    }
}
