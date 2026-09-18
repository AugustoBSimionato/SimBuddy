//
//  SimulatorStore.swift
//  SimBuddy
//
//  Created by Augusto Simionato on 16/08/25.
//

import Accessibility
import Foundation
import Observation

@Observable
@MainActor
final class SimulatorViewModel {
    struct Failure: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    static let refreshesAutomaticallyKey = "refreshesAutomatically"

    private(set) var simulators: [Simulator] = []
    private(set) var hasLoaded = false
    private(set) var busySimulators: Set<Simulator.ID> = []
    private(set) var isUpdatingStatusBar = false
    private(set) var confirmation: String?
    private(set) var simulatorsReceivingFiles: Set<Simulator.ID> = []
    private(set) var sharedFilesRevision = 0
    private(set) var metrics: [Simulator.ID: SimulatorMetrics] = [:]
    private(set) var metricsLoading: Set<Simulator.ID> = []

    var selection: Set<Simulator.ID> = []
    var overrides = StatusBarOverrides()
    var failure: Failure?
    var isImportingFiles = false

    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var confirmationTask: Task<Void, Never>?
    private let simulatorClient: any SimulatorClient

    init(simulatorClient: any SimulatorClient = SimctlClient()) {
        self.simulatorClient = simulatorClient
        UserDefaults.standard.register(defaults: [Self.refreshesAutomaticallyKey: true])
    }

    var bootedSimulators: [Simulator] { simulators.filter(\.isBooted) }

    var selectedBootedSimulators: [Simulator] { simulators(withIDs: selection).filter(\.isBooted) }

    var canUpdateStatusBar: Bool { !isUpdatingStatusBar && !selectedBootedSimulators.isEmpty }
    var canApplyOverrides: Bool { canUpdateStatusBar && !overrides.arguments.isEmpty }

    func simulators(withIDs ids: Set<Simulator.ID>) -> [Simulator] {
        simulators.filter { ids.contains($0.id) }
    }

    func canBoot(_ ids: Set<Simulator.ID>) -> Bool {
        simulators(withIDs: ids).contains { $0.state == .shutdown && !busySimulators.contains($0.id) }
    }

    func canShutdown(_ ids: Set<Simulator.ID>) -> Bool {
        simulators(withIDs: ids).contains { $0.isBooted && !busySimulators.contains($0.id) }
    }

    var selectedSimulator: Simulator? {
        selection.count == 1 ? simulators(withIDs: selection).first : nil
    }

    func canShare(with simulator: Simulator?) -> Bool {
        guard let simulator else { return false }
        return simulator.isBooted && simulator.supportsFileSharing && !simulatorsReceivingFiles.contains(simulator.id)
    }

    // MARK: - Refreshing

    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let result = await simulatorClient.listSimulators()
        guard generation == refreshGeneration else { return }

        if !hasLoaded { hasLoaded = true }
        guard result.succeeded, let simulators = try? SimulatorList.decode(result.standardOutput) else { return }

        if simulators != self.simulators { self.simulators = simulators }
        let simulatorIDs = Set(simulators.map(\.id))
        metrics = metrics.filter { simulatorIDs.contains($0.key) }
        let validSelection = selection.intersection(simulators.map(\.id))
        if validSelection != selection { selection = validSelection }
        await loadMetrics(for: selection)
    }

    func monitor() async {
        await refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            if UserDefaults.standard.bool(forKey: Self.refreshesAutomaticallyKey) {
                await refresh()
            }
        }
    }

    // MARK: - Booting

    func boot(_ ids: Set<Simulator.ID>) async {
        let targets = simulators(withIDs: ids).filter { $0.state == .shutdown && !busySimulators.contains($0.id) }
        await perform(simulatorClient.boot(udid:), on: targets, transitionalState: .booting) {
            String(localized: "Não foi possível iniciar “\($0)”")
        }
    }

    func shutdown(_ ids: Set<Simulator.ID>) async {
        let targets = simulators(withIDs: ids).filter { $0.isBooted && !busySimulators.contains($0.id) }
        await perform(simulatorClient.shutdown(udid:), on: targets, transitionalState: .shuttingDown) {
            String(localized: "Não foi possível encerrar “\($0)”")
        }
    }

    func loadMetrics(for ids: Set<Simulator.ID>) async {
        guard ids.count == 1, let simulator = simulators(withIDs: ids).first,
              !metricsLoading.contains(simulator.id)
        else { return }

        metricsLoading.insert(simulator.id)
        defer { metricsLoading.remove(simulator.id) }

        let diskUsageTask = Task<Int64?, Never> { [dataURL = simulator.dataURL] in
            guard let dataURL else { return nil }
            return await simulatorClient.diskUsage(at: dataURL)
        }
        async let apps = simulatorClient.installedApps(udid: simulator.udid, dataURL: simulator.dataURL)
        metrics[simulator.id] = await SimulatorMetrics(diskUsage: diskUsageTask.value, apps: apps)
    }

    func delete(_ ids: Set<Simulator.ID>) async {
        let targets = simulators(withIDs: ids).filter { !busySimulators.contains($0.id) }
        guard !targets.isEmpty else { return }

        let targetIDs = Set(targets.map(\.id))
        busySimulators.formUnion(targetIDs)
        let client = simulatorClient
        let failures = await withTaskGroup(of: (Simulator, Shell.Result).self) { group in
            for simulator in targets {
                group.addTask {
                    if simulator.isBooted {
                        let shutdown = await client.shutdown(udid: simulator.udid)
                        guard shutdown.succeeded else { return (simulator, shutdown) }
                    }
                    return (simulator, await client.delete(udid: simulator.udid))
                }
            }

            var failures: [(Simulator, Shell.Result)] = []
            for await (simulator, result) in group {
                busySimulators.remove(simulator.id)
                if !result.succeeded { failures.append((simulator, result)) }
            }
            return failures
        }

        await refresh()
        if let (simulator, result) = failures.first {
            failure = Failure(title: String(localized: "Não foi possível excluir “\(simulator.name)”"), message: result.output)
        }
    }

    private func perform(
        _ operation: @escaping @Sendable (String) async -> Shell.Result,
        on targets: [Simulator],
        transitionalState: Simulator.State,
        failureTitle: (String) -> String
    ) async {
        guard !targets.isEmpty else { return }
        let ids = Set(targets.map(\.id))
        busySimulators.formUnion(ids)
        for index in simulators.indices where ids.contains(simulators[index].id) {
            simulators[index].state = transitionalState
        }

        let failures = await withTaskGroup(of: (Simulator, Shell.Result).self) { group in
            for simulator in targets {
                group.addTask { (simulator, await operation(simulator.udid)) }
            }
            var failures: [(Simulator, Shell.Result)] = []
            for await (simulator, result) in group {
                busySimulators.remove(simulator.id)
                if !result.succeeded { failures.append((simulator, result)) }
            }
            return failures
        }

        await refresh()
        if let (simulator, result) = failures.first {
            failure = Failure(title: failureTitle(simulator.name), message: result.output)
        }
    }

    // MARK: - Sharing

    func share(_ urls: [URL], with simulator: Simulator) async {
        guard !urls.isEmpty, canShare(with: simulator), let dataURL = simulator.dataURL else { return }
        simulatorsReceivingFiles.insert(simulator.id)
        defer {
            simulatorsReceivingFiles.remove(simulator.id)
            sharedFilesRevision += 1
        }

        var failures: [(name: String, message: String)] = []
        for url in urls {
            if SimulatorFiles.isPhotoLibraryMedia(url), await simulatorClient.addMedia(url, to: simulator.udid).succeeded {
                continue
            }
            do {
                try await SimulatorFiles.copy(url, toFilesIn: dataURL)
            } catch {
                failures.append((url.lastPathComponent, error.localizedDescription))
            }
        }

        if let (name, message) = failures.first {
            failure = Failure(
                title: String(localized: "Não foi possível enviar “\(name)” para “\(simulator.name)”"),
                message: message
            )
        } else if urls.count == 1 {
            confirm(String(localized: "“\(urls[0].lastPathComponent)” enviado para “\(simulator.name)”"))
        } else {
            confirm(String(localized: "\(urls.count) itens enviados para “\(simulator.name)”"))
        }
    }

    func deleteSharedItems(_ items: [SharedItem]) async {
        defer { sharedFilesRevision += 1 }
        do {
            try await SimulatorFiles.remove(items)
        } catch {
            failure = Failure(title: String(localized: "Não foi possível excluir os itens"), message: error.localizedDescription)
        }
    }

    // MARK: - Status bar

    func applyOverrides() async {
        let arguments = overrides.arguments
        await updateStatusBar(
            failureTitle: String(localized: "Não foi possível aplicar as alterações"),
            confirmation: { String(localized: "Alterações aplicadas a \($0) simuladores") }
        ) {
            await simulatorClient.overrideStatusBar($0, arguments: arguments)
        }
    }

    func clearOverrides() async {
        await updateStatusBar(
            failureTitle: String(localized: "Não foi possível limpar as alterações"),
            confirmation: { String(localized: "Alterações removidas de \($0) simuladores") }
        ) {
            await simulatorClient.clearStatusBar($0)
        }
    }

    func applyClassicPreset() async -> Bool {
        await simulatorClient.overrideStatusBar(.allBooted, arguments: StatusBarOverrides.classic.arguments).succeeded
    }

    func clearAllBooted() async -> Bool {
        await simulatorClient.clearStatusBar(.allBooted).succeeded
    }

    private func updateStatusBar(
        failureTitle: String,
        confirmation: (Int) -> String,
        operation: (Shell.StatusBarTarget) async -> Shell.Result
    ) async {
        let targets = selectedBootedSimulators
        guard !isUpdatingStatusBar, !targets.isEmpty else { return }
        isUpdatingStatusBar = true
        defer { isUpdatingStatusBar = false }

        let result = await operation(.simulators(targets.map(\.udid)))
        if result.succeeded {
            confirm(confirmation(targets.count))
        } else {
            failure = Failure(title: failureTitle, message: result.output)
        }
    }

    private func confirm(_ message: String) {
        confirmation = message
        AccessibilityNotification.Announcement(message).post()
        confirmationTask?.cancel()
        confirmationTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { confirmation = nil }
        }
    }
}
