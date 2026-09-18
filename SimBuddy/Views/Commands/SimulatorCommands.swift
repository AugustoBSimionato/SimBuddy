//
//  SimulatorCommands.swift
//  SimBuddy
//
//  Created by Augusto Simionato on 11/09/26.
//

import SwiftUI

struct SimulatorCommands: Commands {
    let viewModel: SimulatorViewModel

    var body: some Commands {
        CommandMenu("Simulador") {
            Button("Atualizar lista", systemImage: "arrow.clockwise") {
                Task { await viewModel.refresh() }
            }
            .keyboardShortcut("r")

            Divider()

            Button("Iniciar", systemImage: "play") {
                Task { await viewModel.boot(viewModel.selection) }
            }
            .disabled(!viewModel.canBoot(viewModel.selection))

            Button("Encerrar", systemImage: "stop") {
                Task { await viewModel.shutdown(viewModel.selection) }
            }
            .disabled(!viewModel.canShutdown(viewModel.selection))

            Divider()

            Button("Enviar arquivos…", systemImage: "square.and.arrow.up") {
                viewModel.isImportingFiles = true
            }
            .keyboardShortcut("o")
            .disabled(!viewModel.canShare(with: viewModel.selectedSimulator))

            Divider()

            Button("Aplicar alterações", systemImage: "checkmark") {
                Task { await viewModel.applyOverrides() }
            }
            .keyboardShortcut(.return)
            .disabled(!viewModel.canApplyOverrides)

            Button("Limpar alterações", systemImage: "eraser") {
                Task { await viewModel.clearOverrides() }
            }
            .keyboardShortcut("k")
            .disabled(!viewModel.canUpdateStatusBar)
        }
    }
}
