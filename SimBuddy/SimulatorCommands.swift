//
//  SimulatorCommands.swift
//  SimBuddy
//
//  Created by Augusto Simionato on 11/09/26.
//

import SwiftUI

struct SimulatorCommands: Commands {
    let store: SimulatorStore

    var body: some Commands {
        CommandMenu("Simulador") {
            Button("Atualizar lista", systemImage: "arrow.clockwise") {
                Task { await store.refresh() }
            }
            .keyboardShortcut("r")

            Divider()

            Button("Iniciar", systemImage: "play") {
                Task { await store.boot(store.selection) }
            }
            .disabled(!store.canBoot(store.selection))

            Button("Encerrar", systemImage: "stop") {
                Task { await store.shutdown(store.selection) }
            }
            .disabled(!store.canShutdown(store.selection))

            Divider()

            Button("Enviar arquivos…", systemImage: "square.and.arrow.up") {
                store.isImportingFiles = true
            }
            .keyboardShortcut("o")
            .disabled(!store.canShare(with: store.selectedSimulator))

            Divider()

            Button("Aplicar alterações", systemImage: "checkmark") {
                Task { await store.applyOverrides() }
            }
            .keyboardShortcut(.return)
            .disabled(!store.canApplyOverrides)

            Button("Limpar alterações", systemImage: "eraser") {
                Task { await store.clearOverrides() }
            }
            .keyboardShortcut("k")
            .disabled(!store.canUpdateStatusBar)
        }
    }
}
