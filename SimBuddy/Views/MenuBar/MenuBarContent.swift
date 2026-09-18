//
//  MenuBarContent.swift
//  SimBuddy
//
//  Created by Augusto Simionato on 11/09/26.
//

import SwiftUI

struct MenuBarContent: View {
    @Environment(SimulatorViewModel.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Aplicar predefinição (9:41, bateria cheia, sinal máximo)", systemImage: "wand.and.sparkles") {
            Task { if await !store.applyClassicPreset() { NSSound.beep() } }
        }

        Button("Limpar alterações", systemImage: "eraser") {
            Task { if await !store.clearAllBooted() { NSSound.beep() } }
        }

        Divider()

        Button("Abrir o SimBuddy", systemImage: "macwindow") {
            openWindow(id: SimBuddyApp.mainWindowID)
            NSApp.activate()
        }

        SettingsLink {
            Label("Ajustes…", systemImage: "gearshape")
        }

        Divider()

        Button("Encerrar o SimBuddy", systemImage: "power") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
