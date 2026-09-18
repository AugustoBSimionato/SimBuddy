//
//  SimulatorSidebar.swift
//  SimBuddy
//
//  Created by Augusto Simionato on 11/09/26.
//

import SwiftUI

struct SimulatorSidebar: View {
    @Environment(SimulatorViewModel.self) private var store
    let searchText: String
    @Binding var showsRunningOnly: Bool
    @State private var pendingDeletion: [Simulator]?

    var body: some View {
        @Bindable var store = store
        let sections = visibleSections
        let sidebarSelection = Binding<Set<SidebarItem>>(
            get: {
                store.selection.isEmpty
                    ? [.home]
                    : Set(store.selection.map(SidebarItem.simulator))
            },
            set: { items in
                store.selection = Set(items.compactMap(\.simulatorID))
            }
        )

        List(selection: sidebarSelection) {
            Section {
                Label("Início", systemImage: "house")
                    .tag(SidebarItem.home)
            }
            ForEach(sections, id: \.key) { section in
                Section(section.key.name) {
                    ForEach(section.value) { simulator in
                        SimulatorRow(simulator: simulator, isBusy: store.busySimulators.contains(simulator.id))
                            .tag(SidebarItem.simulator(simulator.id))
                    }
                }
            }
        }
        .contextMenu(forSelectionType: SidebarItem.self) { items in
            let ids = Set(items.compactMap(\.simulatorID))
            SimulatorContextMenu(ids: ids) { simulators in
                pendingDeletion = simulators
            }
        } primaryAction: { items in
            let ids = Set(items.compactMap(\.simulatorID))
            Task { await store.boot(ids) }
        }
        .overlay {
            emptyState(hasVisibleSimulators: !sections.isEmpty)
        }
        .task(id: store.selection) {
            await store.loadMetrics(for: store.selection)
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { simulators in
            Button("Excluir", role: .destructive) {
                Task { await store.delete(Set(simulators.map(\.id))) }
            }
        } message: { simulators in
            Text(simulators.count == 1
                ? "O simulador e todos os seus dados serão removidos permanentemente."
                : "Os simuladores e todos os seus dados serão removidos permanentemente.")
        }
    }

    private var visibleSections: [(key: Runtime, value: [Simulator])] {
        let visible = store.simulators.filter { simulator in
            (!showsRunningOnly || simulator.isBooted)
                && (searchText.isEmpty
                    || simulator.name.localizedStandardContains(searchText)
                    || simulator.runtime.name.localizedStandardContains(searchText))
        }
        return Dictionary(grouping: visible, by: \.runtime).sorted { $0.key < $1.key }
    }

    private var deletionTitle: String {
        let count = pendingDeletion?.count ?? 0
        return count == 1 ? "Excluir simulador?" : "Excluir \(count) simuladores?"
    }

    @ViewBuilder
    private func emptyState(hasVisibleSimulators: Bool) -> some View {
        if !store.hasLoaded {
            ProgressView()
        } else if store.simulators.isEmpty {
            ContentUnavailableView(
                "Nenhum simulador",
                systemImage: "iphone.slash",
                description: Text("Crie simuladores no Xcode para vê-los aqui.")
            )
        } else if !hasVisibleSimulators, !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else if !hasVisibleSimulators {
            ContentUnavailableView {
                Label("Nenhum simulador em execução", systemImage: "iphone.slash")
            } description: {
                Text("Inicie um simulador para alterar a barra de status dele.")
            } actions: {
                Button("Mostrar todos") { showsRunningOnly = false }
            }
        }
    }
}

private enum SidebarItem: Hashable {
    case home
    case simulator(Simulator.ID)

    var simulatorID: Simulator.ID? {
        guard case .simulator(let id) = self else { return nil }
        return id
    }
}

private struct SimulatorRow: View {
    let simulator: Simulator
    let isBusy: Bool

    var body: some View {
        Label {
            HStack {
                Text(simulator.name)
                    .lineLimit(1)
                Spacer()
                statusIndicator
            }
        } icon: {
            Image(systemName: simulator.symbolName)
        }
        .help(Text(verbatim: "\(simulator.runtime.name) — \(simulator.udid)"))
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if isBusy || simulator.state == .booting || simulator.state == .shuttingDown {
            ProgressView()
                .controlSize(.small)
        } else if simulator.isBooted {
            Circle()
                .fill(.green)
                .frame(width: 7, height: 7)
                .help("Em execução")
                .accessibilityLabel("Em execução")
        }
    }
}

private struct SimulatorContextMenu: View {
    @Environment(SimulatorViewModel.self) private var store
    let ids: Set<Simulator.ID>
    let requestDeletion: ([Simulator]) -> Void

    var body: some View {
        let canBoot = store.canBoot(ids)
        let canShutdown = store.canShutdown(ids)
        let simulators = store.simulators(withIDs: ids)

        if let simulator = simulators.only {
            simulatorDetails(simulator)
            Divider()
        }

        if canBoot {
            Button("Iniciar", systemImage: "play") {
                Task { await store.boot(ids) }
            }
        }
        if canShutdown {
            Button("Encerrar", systemImage: "stop") {
                Task { await store.shutdown(ids) }
            }
        }
        if !ids.isEmpty {
            if canBoot || canShutdown {
                Divider()
            }
            Button("Copiar UDID", systemImage: "doc.on.doc") {
                let udids = simulators.map(\.udid)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(udids.joined(separator: "\n"), forType: .string)
            }
            if let simulator = simulators.only, let dataURL = simulator.dataURL {
                Button("Copiar caminho do simulador", systemImage: "document.on.document") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(dataURL.path(percentEncoded: false), forType: .string)
                }
                Button("Mostrar no Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([dataURL])
                }
            }
            Divider()
            Button("Excluir simulador", systemImage: "trash", role: .destructive) {
                requestDeletion(simulators)
            }
        }
    }

    @ViewBuilder
    private func simulatorDetails(_ simulator: Simulator) -> some View {
        let metrics = store.metrics[simulator.id]
        let isLoading = store.metricsLoading.contains(simulator.id)

        Button("\(simulator.deviceTypeName) · \(simulator.runtime.name)") {}
            .disabled(true)
        Button("Status: \(simulator.stateName)") {}
            .disabled(true)
        if let diskUsage = metrics?.diskUsage {
            Button("Em disco: \(ByteCountFormatter.string(fromByteCount: diskUsage, countStyle: .file))") {}
                .disabled(true)
        } else if isLoading {
            Button("Carregando detalhes…") {}
                .disabled(true)
        }
        Menu(metrics.map { "Apps instalados (\($0.apps.count))" } ?? "Apps instalados") {
            if isLoading {
                Button("Carregando apps…") {}
                    .disabled(true)
            } else if let metrics, metrics.apps.isEmpty {
                Button("Nenhum app encontrado") {}
                    .disabled(true)
            } else if let metrics {
                ForEach(metrics.apps) { app in
                    Button("\(app.name) — \(app.bundleIdentifier)") {}
                        .disabled(true)
                }
            } else {
                Button("Selecione o simulador para carregar os apps") {}
                    .disabled(true)
            }
        }
    }
}

private extension Collection {
    var only: Element? { count == 1 ? first : nil }
}
