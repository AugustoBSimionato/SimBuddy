//
//  OverridesForm.swift
//  SimBuddy
//
//  Created by Augusto Simionato on 11/09/26.
//

import SwiftUI

struct OverridesForm: View {
    @Environment(SimulatorStore.self) private var store

    var body: some View {
        @Bindable var store = store

        Form {
            Section {
                StatusBarPreview(overrides: store.overrides)
            }

            Section {
                Picker("Aplicar a", selection: $store.target) {
                    Text("Todos os simuladores em execução").tag(SimulatorStore.Target.allBooted)
                    Text("Simuladores selecionados na barra lateral").tag(SimulatorStore.Target.selection)
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("Destino")
            } footer: {
                targetFooter
            }

            Section("Hora e bateria") {
                OverrideRow("Hora", isOn: $store.overrides.overridesTime) {
                    TextField("Hora", text: $store.overrides.time, prompt: Text(verbatim: "9:41"))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                }

                OverrideRow("Estado da bateria", isOn: $store.overrides.overridesBatteryState) {
                    Picker("Estado da bateria", selection: $store.overrides.batteryState) {
                        ForEach(BatteryState.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                OverrideRow("Nível da bateria", isOn: $store.overrides.overridesBatteryLevel) {
                    HStack {
                        Slider(value: $store.overrides.batteryLevel, in: 0...100) {
                            Text("Nível da bateria")
                        }
                        .labelsHidden()
                        .frame(maxWidth: 200)

                        Text((store.overrides.batteryLevel / 100).formatted(.percent))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 40, alignment: .trailing)
                    }
                }
            }

            Section("Conectividade") {
                OverrideRow("Wi‑Fi", isOn: $store.overrides.overridesWiFi) {
                    HStack {
                        Picker("Modo do Wi‑Fi", selection: $store.overrides.wifiMode) {
                            ForEach(WiFiMode.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()

                        SignalPicker("Sinal do Wi‑Fi", symbol: "wifi", maximum: 3, selection: $store.overrides.wifiBars)
                            .disabled(store.overrides.wifiMode != .active)
                    }
                }

                OverrideRow("Celular", isOn: $store.overrides.overridesCellular) {
                    HStack {
                        Picker("Modo do celular", selection: $store.overrides.cellularMode) {
                            ForEach(CellularMode.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()

                        SignalPicker("Sinal do celular", symbol: "cellularbars", maximum: 4, selection: $store.overrides.cellularBars)
                            .disabled(store.overrides.cellularMode != .active)
                    }
                }

                OverrideRow("Rede de dados", isOn: $store.overrides.overridesDataNetwork) {
                    Picker("Rede de dados", selection: $store.overrides.dataNetwork) {
                        Text("Wi‑Fi").tag(DataNetwork.wifi)
                        Divider()
                        ForEach(DataNetwork.cellularCases) { network in
                            Text(verbatim: network.badge ?? network.rawValue).tag(network)
                        }
                        Divider()
                        Text("Ocultar").tag(DataNetwork.hide)
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                OverrideRow("Operadora", isOn: $store.overrides.overridesOperatorName) {
                    TextField("Operadora", text: $store.overrides.operatorName, prompt: Text("Nome da operadora"))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 200)
                }
            }
        }
        .formStyle(.grouped)
        .toolbar { toolbarContent }
    }

    @ViewBuilder
    private var targetFooter: some View {
        let count = store.targetedSimulators.count
        switch (store.target, count) {
        case (.allBooted, 0):
            Text("Nenhum simulador em execução no momento.")
        case (.allBooted, _):
            Text("As alterações serão aplicadas a \(count) simuladores em execução.")
        case (.selection, 0):
            Text("Selecione na barra lateral os simuladores em execução que devem receber as alterações.")
        case (.selection, _):
            Text("As alterações serão aplicadas a \(count) simuladores selecionados.")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button("Iniciar", systemImage: "play.fill") {
                Task { await store.boot(store.selection) }
            }
            .help("Iniciar os simuladores selecionados")
            .disabled(!store.canBoot(store.selection))

            Button("Encerrar", systemImage: "stop.fill") {
                Task { await store.shutdown(store.selection) }
            }
            .help("Encerrar os simuladores selecionados")
            .disabled(!store.canShutdown(store.selection))
        }

        ToolbarSpacer(.fixed)

        ToolbarItem {
            Button("Limpar alterações", systemImage: "eraser") {
                Task { await store.clearOverrides() }
            }
            .help("Remover as alterações da barra de status")
            .disabled(!store.canUpdateStatusBar)
        }

        ToolbarSpacer(.fixed)

        ToolbarItem {
            Button("Aplicar") {
                Task { await store.applyOverrides() }
            }
            .buttonStyle(.glassProminent)
            .help("Aplicar as alterações à barra de status")
            .disabled(!store.canApplyOverrides)
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

private struct OverrideRow<Content: View>: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool
    let content: Content

    init(_ title: LocalizedStringKey, isOn: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.title = title
        _isOn = isOn
        self.content = content()
    }

    var body: some View {
        LabeledContent {
            content
                .disabled(!isOn)
        } label: {
            HStack(spacing: 6) {
                Toggle(title, isOn: $isOn)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                Text(title)
                    .accessibilityHidden(true)
                    .onTapGesture { isOn.toggle() }
            }
        }
    }
}

private struct SignalPicker: View {
    let title: LocalizedStringKey
    let symbol: String
    let maximum: Int
    @Binding var selection: Int

    init(_ title: LocalizedStringKey, symbol: String, maximum: Int, selection: Binding<Int>) {
        self.title = title
        self.symbol = symbol
        self.maximum = maximum
        _selection = selection
    }

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(0...maximum, id: \.self) { bars in
                Image(systemName: symbol, variableValue: Double(bars) / Double(maximum))
                    .accessibilityLabel(Text("\(bars) barras"))
                    .tag(bars)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help(title)
    }
}
