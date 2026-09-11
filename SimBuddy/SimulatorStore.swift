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
final class SimulatorStore {
    enum Target: Hashable {
        case allBooted
        case selection
    }

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

    var selection: Set<Simulator.ID> = []
    var target: Target = .allBooted
    var overrides = StatusBarOverrides()
    var failure: Failure?

    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var confirmationTask: Task<Void, Never>?

    init() {
        UserDefaults.standard.register(defaults: [Self.refreshesAutomaticallyKey: true])
    }

    var bootedSimulators: [Simulator] { simulators.filter(\.isBooted) }

    var targetedSimulators: [Simulator] {
        switch target {
        case .allBooted: bootedSimulators
        case .selection: simulators(withIDs: selection).filter(\.isBooted)
        }
    }

    var canUpdateStatusBar: Bool { !isUpdatingStatusBar && !targetedSimulators.isEmpty }
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

    // MARK: - Refreshing

    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let result = await Shell.listSimulators()
        guard generation == refreshGeneration else { return }

        if !hasLoaded { hasLoaded = true }
        guard result.succeeded, let simulators = try? SimulatorList.decode(result.standardOutput) else { return }

        if simulators != self.simulators { self.simulators = simulators }
        let validSelection = selection.intersection(simulators.map(\.id))
        if validSelection != selection { selection = validSelection }
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
        await perform(Shell.boot(udid:), on: targets, transitionalState: .booting) {
            String(localized: "Não foi possível iniciar “\($0)”")
        }
    }

    func shutdown(_ ids: Set<Simulator.ID>) async {
        let targets = simulators(withIDs: ids).filter { $0.isBooted && !busySimulators.contains($0.id) }
        await perform(Shell.shutdown(udid:), on: targets, transitionalState: .shuttingDown) {
            String(localized: "Não foi possível encerrar “\($0)”")
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

    // MARK: - Status bar

    func applyOverrides() async {
        let arguments = overrides.arguments
        await updateStatusBar(
            failureTitle: String(localized: "Não foi possível aplicar as alterações"),
            confirmation: { String(localized: "Alterações aplicadas a \($0) simuladores") }
        ) {
            await Shell.overrideStatusBar($0, arguments: arguments)
        }
    }

    func clearOverrides() async {
        await updateStatusBar(
            failureTitle: String(localized: "Não foi possível limpar as alterações"),
            confirmation: { String(localized: "Alterações removidas de \($0) simuladores") }
        ) {
            await Shell.clearStatusBar($0)
        }
    }

    func applyClassicPreset() async -> Bool {
        await Shell.overrideStatusBar(.allBooted, arguments: StatusBarOverrides.classic.arguments).succeeded
    }

    func clearAllBooted() async -> Bool {
        await Shell.clearStatusBar(.allBooted).succeeded
    }

    private func updateStatusBar(
        failureTitle: String,
        confirmation: (Int) -> String,
        operation: (Shell.StatusBarTarget) async -> Shell.Result
    ) async {
        let targets = targetedSimulators
        guard !isUpdatingStatusBar, !targets.isEmpty else { return }
        isUpdatingStatusBar = true
        defer { isUpdatingStatusBar = false }

        let shellTarget: Shell.StatusBarTarget = target == .allBooted ? .allBooted : .simulators(targets.map(\.udid))
        let result = await operation(shellTarget)
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
