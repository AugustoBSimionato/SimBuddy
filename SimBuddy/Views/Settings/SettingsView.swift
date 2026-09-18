//
//  SettingsView.swift
//  SimBuddy
//
//  Created by Augusto Simionato on 11/09/26.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(SimulatorViewModel.refreshesAutomaticallyKey) private var refreshesAutomatically = true

    var body: some View {
        Form {
            Section {
                Toggle("Atualizar a lista de simuladores automaticamente", isOn: $refreshesAutomatically)
            } footer: {
                Text("O SimBuddy verifica a cada poucos segundos se algum simulador foi iniciado ou encerrado.")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 460)
        .fixedSize()
    }
}
