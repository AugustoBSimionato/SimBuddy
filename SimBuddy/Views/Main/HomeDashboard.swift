//
//  HomeDashboard.swift
//  SimBuddy
//
//  Created by Augusto Simionato on 17/09/26.
//

import AppKit
import SwiftUI

struct HomeDashboard: View {
    @Environment(SimulatorViewModel.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Visão geral")
                        .font(.largeTitle.weight(.bold))
                    Text(summary)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    DashboardMetric(title: "Em execução", value: store.bootedSimulators.count, symbol: "play.circle.fill", tint: .green)
                    DashboardMetric(title: "Disponíveis", value: store.simulators.count, symbol: "iphone", tint: .blue)
                }

                GroupBox("Ações rápidas") {
                    HStack(spacing: 12) {
                        Button("Atualizar lista", systemImage: "arrow.clockwise") {
                            Task { await store.refresh() }
                        }

                        Button("Aplicar predefinição clássica", systemImage: "wand.and.sparkles") {
                            Task {
                                if await !store.applyClassicPreset() {
                                    NSSound.beep()
                                }
                            }
                        }
                        .disabled(store.bootedSimulators.isEmpty)

                        Button("Limpar alterações", systemImage: "eraser") {
                            Task {
                                if await !store.clearAllBooted() {
                                    NSSound.beep()
                                }
                            }
                        }
                        .disabled(store.bootedSimulators.isEmpty)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }

                GroupBox("Simuladores em execução") {
                    if store.bootedSimulators.isEmpty {
                        ContentUnavailableView(
                            "Nenhum simulador em execução",
                            systemImage: "iphone.slash",
                            description: Text("Inicie um simulador pela barra lateral para personalizar a barra de status.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(store.bootedSimulators) { simulator in
                                Button {
                                    store.selection = [simulator.id]
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: simulator.symbolName)
                                            .font(.title3)
                                            .foregroundStyle(.tint)
                                            .frame(width: 24)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(simulator.name)
                                            Text(simulator.runtime.name)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .contentShape(.rect)
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(.plain)

                                if simulator.id != store.bootedSimulators.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(32)
        }
    }

    private var summary: String {
        if store.simulators.isEmpty {
            return "Crie simuladores no Xcode para gerenciá-los aqui."
        }
        return String(localized: "\(store.bootedSimulators.count) em execução de \(store.simulators.count) simuladores disponíveis")
    }
}

private struct DashboardMetric: View {
    let title: LocalizedStringKey
    let value: Int
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)

            Text(value, format: .number)
                .font(.title.bold())
                .monospacedDigit()

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary, in: .rect(cornerRadius: 12))
    }
}
