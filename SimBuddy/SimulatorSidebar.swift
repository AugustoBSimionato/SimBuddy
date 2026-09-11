//
//  SimulatorSidebar.swift
//  SimBuddy
//
//  Created by Augusto Simionato on 11/09/26.
//

import SwiftUI

struct SimulatorSidebar: View {
    @Environment(SimulatorStore.self) private var store
    let searchText: String
    @Binding var showsRunningOnly: Bool

    var body: some View {
        @Bindable var store = store
        let sections = visibleSections

        List(selection: $store.selection) {
            ForEach(sections, id: \.key) { section in
                Section(section.key.name) {
                    ForEach(section.value) { simulator in
                        SimulatorRow(simulator: simulator, isBusy: store.busySimulators.contains(simulator.id))
                    }
                }
            }
        }
        .contextMenu(forSelectionType: Simulator.ID.self) { ids in
            SimulatorContextMenu(ids: ids)
        } primaryAction: { ids in
            Task { await store.boot(ids) }
        }
        .overlay {
            emptyState(hasVisibleSimulators: !sections.isEmpty)
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
    @Environment(SimulatorStore.self) private var store
    let ids: Set<Simulator.ID>

    var body: some View {
        let canBoot = store.canBoot(ids)
        let canShutdown = store.canShutdown(ids)

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
                let udids = store.simulators(withIDs: ids).map(\.udid)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(udids.joined(separator: "\n"), forType: .string)
            }
        }
    }
}
