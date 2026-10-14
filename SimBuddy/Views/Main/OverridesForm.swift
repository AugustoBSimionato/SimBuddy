//
//  OverridesForm.swift
//  SimBuddy
//
//  Created by Augusto Simionato on 11/09/26.
//

import AgentCore
import SwiftUI

enum SimulatorDetailPanel: Hashable {
  case simulator, protection
}

struct OverridesForm: View {
  @Environment(SimulatorViewModel.self) private var store

  @State private var panel: SimulatorDetailPanel

  init(initialPanel: SimulatorDetailPanel = .simulator) {
    _panel = State(initialValue: initialPanel)
  }

  var body: some View {
    Group {
      if store.selection.isEmpty {
        HomeDashboard()
      } else {
        VStack(spacing: 0) {
          Picker("Seção do simulador", selection: $panel) {
            Text("Simulador").tag(SimulatorDetailPanel.simulator)
            Text("Proteção contra agentes").tag(SimulatorDetailPanel.protection)
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .frame(width: 340)
          .frame(maxWidth: .infinity)
          .padding(.horizontal, 20)
          .padding(.vertical, 12)
          .background(.bar)

          Divider()

          switch panel {
          case .simulator:
            SimulatorCustomizationForm()
          case .protection:
            SimulatorAgentProtectionView()
          }
        }
      }
    }
    .toolbar {
      if !store.selection.isEmpty {
        toolbarContent
      }
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

    if panel == .simulator {
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
}

private struct SimulatorCustomizationForm: View {
  @Environment(SimulatorViewModel.self) private var store

  var body: some View {
    @Bindable var store = store

    Form {
      Section {
        StatusBarPreview(overrides: store.overrides)
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
            Slider(value: $store.overrides.batteryLevel, in: 0...100, step: 1) {
              Text("Nível da bateria")
            }
            .labelsHidden()
            .frame(maxWidth: 200)

            Text(
              (store.overrides.batteryLevel / 100).formatted(
                .percent.precision(.fractionLength(0)))
            )
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

            SignalPicker(
              "Sinal do Wi‑Fi", symbol: "wifi", maximum: 3, selection: $store.overrides.wifiBars
            )
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

            SignalPicker(
              "Sinal do celular", symbol: "cellularbars", maximum: 4,
              selection: $store.overrides.cellularBars
            )
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
          TextField(
            "Operadora", text: $store.overrides.operatorName, prompt: Text("Nome da operadora")
          )
          .labelsHidden()
          .multilineTextAlignment(.trailing)
          .frame(maxWidth: 200)
        }
      }

      SharingSection()
    }
    .formStyle(.grouped)
  }
}

private struct SimulatorAgentProtectionView: View {
  @Environment(SimulatorViewModel.self) private var store

  var body: some View {
    if let simulator = store.selectedSimulator {
      Form {
        AgentProtectionSection(monitor: store.agentMonitor, simulatorID: simulator.id)
      }
      .formStyle(.grouped)
    } else {
      ContentUnavailableView(
        "Selecione um simulador",
        systemImage: "lock.shield",
        description: Text("Selecione apenas um simulador na barra lateral para configurar sua proteção contra agentes.")
      )
    }
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

#Preview("Simulador") {
  @Previewable @State var store = SimulatorDetailPreview.makeStore()
  OverridesForm()
    .environment(store)
    .frame(width: 720, height: 640)
    .task {
      await store.refresh()
      if let simulator = store.bootedSimulators.first ?? store.simulators.first {
        store.selection = [simulator.id]
      }
    }
}

#Preview("Proteção contra agentes") {
  @Previewable @State var store = SimulatorDetailPreview.makeStore()
  OverridesForm(initialPanel: .protection)
    .environment(store)
    .frame(width: 720, height: 640)
    .task {
      await store.refresh()
      if let simulator = store.bootedSimulators.first ?? store.simulators.first {
        store.selection = [simulator.id]
      }
    }
}

private enum SimulatorDetailPreview {
  static let simulatorID = "11111111-1111-1111-1111-111111111111"

  static func makeStore() -> SimulatorViewModel {
    let monitor = AgentMonitor(
      persistence: AgentPersistence(directory: URL.temporaryDirectory.appending(path: "SimBuddyDetailPreview")),
      notificationsEnabled: false
    )
    let store = SimulatorViewModel(simulatorClient: SimulatorDetailPreviewClient(), agentMonitor: monitor)
    store.selection = [simulatorID]
    return store
  }
}

nonisolated private struct SimulatorDetailPreviewClient: SimulatorClient {
  func listSimulators() async -> Shell.Result {
    let data = Data(#"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"udid":"11111111-1111-1111-1111-111111111111","name":"iPhone 18 Pro","state":"Booted","isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro"}]},"pairs":{}}"#.utf8)
    return Shell.Result(exitCode: 0, standardOutput: data, standardError: "")
  }

  func boot(udid: String) async -> Shell.Result { .success }
  func shutdown(udid: String) async -> Shell.Result { .success }
  func delete(udid: String) async -> Shell.Result { .success }
  func diskUsage(at url: URL) async -> Int64? { nil }
  func installedApps(udid: String, dataURL: URL?) async -> [SimulatorMetrics.App] { [] }
  func addMedia(_ url: URL, to udid: String) async -> Shell.Result { .success }
  func overrideStatusBar(_ target: Shell.StatusBarTarget, arguments: [String]) async -> Shell.Result { .success }
  func clearStatusBar(_ target: Shell.StatusBarTarget) async -> Shell.Result { .success }
}
