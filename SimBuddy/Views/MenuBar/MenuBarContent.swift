//
//  MenuBarContent.swift
//  SimBuddy
//
//  Created by Augusto Simionato on 11/09/26.
//

import AgentCore
import SwiftUI

struct MenuBarContent: View {
    @Environment(SimulatorViewModel.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            MenuBarSimulators(store: store)
            MenuBarQuickActions(store: store)
            MenuBarAgents(monitor: store.agentMonitor, openMonitoring: openMonitoring)
            MenuBarOperations(monitor: store.agentMonitor, openMonitoring: openMonitoring)
            MenuBarConnections(monitor: store.agentMonitor)

            Section("Aplicativo") {
                Button("Abrir o SimBuddy", systemImage: "macwindow", action: openMainWindow)

                SettingsLink {
                    Label("Ajustes…", systemImage: "gearshape")
                }
            }

            Divider()

            Button("Encerrar o SimBuddy", systemImage: "power") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .labelStyle(.titleAndIcon)
    }

    private func openMainWindow() {
        openWindow(id: SimBuddyApp.mainWindowID)
        NSApp.activate()
    }

    private func openMonitoring() {
        store.showsAgentMonitoring = true
        openMainWindow()
    }
}

private struct MenuBarSimulators: View {
    let store: SimulatorViewModel

    var body: some View {
        Section {
            if store.bootedSimulators.isEmpty {
                Text("Nenhum simulador em execução")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.bootedSimulators) { simulator in
                    Label {
                        Text(verbatim: "\(simulator.name) · \(simulator.runtime.name)")
                    } icon: {
                        Image(systemName: store.agentMonitor.protection(for: simulator.id).enabled ? "shield.fill" : simulator.symbolName)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Simuladores em execução (\(store.bootedSimulators.count))")
        }
    }
}

private struct MenuBarQuickActions: View {
    let store: SimulatorViewModel

    var body: some View {
        Section("Ações rápidas") {
            Button {
                Task { if await !store.applyClassicPreset() { NSSound.beep() } }
            } label: {
                Label("Aplicar predefinição clássica", systemImage: "wand.and.sparkles")
                Text("9:41 · bateria cheia · sinal máximo")
            }
            .disabled(store.bootedSimulators.isEmpty || store.isUpdatingStatusBar)

            Button("Limpar alterações", systemImage: "eraser") {
                Task { if await !store.clearAllBooted() { NSSound.beep() } }
            }
            .disabled(store.bootedSimulators.isEmpty || store.isUpdatingStatusBar)
        }
    }
}

private struct MenuBarAgents: View {
    let monitor: AgentMonitor
    let openMonitoring: () -> Void

    var body: some View {
        Section("Agentes") {
            Button("Monitoramento de agentes", systemImage: monitor.enabled ? "shield.fill" : "shield", action: openMonitoring)

            Text(monitor.enabled ? LocalizedStringResource("Monitoramento ativado") : LocalizedStringResource("Monitoramento desativado"))
                .foregroundStyle(.secondary)
            Text("\(monitor.protectedCount) simuladores protegidos")
                .foregroundStyle(.secondary)
        }
    }
}

private struct MenuBarOperations: View {
    let monitor: AgentMonitor
    let openMonitoring: () -> Void

    var body: some View {
        Section {
            if monitor.activeOperations.isEmpty {
                Text("Nenhuma operação em andamento")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(monitor.activeOperations) { operation in
                    MenuBarOperation(event: operation.event, openMonitoring: openMonitoring)
                }
            }
        } header: {
            Text("Operações em andamento (\(monitor.activeOperations.count))")
        }
    }
}

private struct MenuBarOperation: View {
    let event: AgentEvent
    let openMonitoring: () -> Void

    var body: some View {
        Button(action: openMonitoring) {
            Label {
                if event.deviceNames.isEmpty {
                    Text(event.operationTitle)
                } else {
                    Text(verbatim: "\(event.operationTitle) · \(event.deviceNames.joined(separator: ", "))")
                }
            } icon: {
                Image(systemName: event.outcome == .queued ? "clock" : "gearshape.2")
            }
            Text(event.outcome == .queued ? LocalizedStringResource("Na fila") : LocalizedStringResource("Em execução"))
        }
    }
}

private struct MenuBarConnections: View {
    let monitor: AgentMonitor

    var body: some View {
        Section {
            if monitor.sessions.isEmpty {
                Text("Nenhum cliente conectado")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(monitor.sessions) { session in
                    Text(verbatim: "\(session.clientName) · \(session.id.uuidString.prefix(8))")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Conexões MCP (\(monitor.sessions.count))")
        }
    }
}
