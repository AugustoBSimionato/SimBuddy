import AgentCore
import AppKit
import SwiftUI
import UserNotifications

enum AgentMonitoringPanel: Hashable {
    case monitoring, history
}

struct AgentMonitoringView: View {
    @Bindable var monitor: AgentMonitor
    @State private var panel: AgentMonitoringPanel
    @State private var historyFilter = AgentHistoryFilter()

    init(monitor: AgentMonitor, initialPanel: AgentMonitoringPanel = .monitoring) {
        self.monitor = monitor
        _panel = State(initialValue: initialPanel)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Seção do monitoramento", selection: $panel) {
                Text("Monitoramento").tag(AgentMonitoringPanel.monitoring)
                Text("Histórico").tag(AgentMonitoringPanel.history)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 280)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)

            Divider()

            switch panel {
            case .monitoring:
                AgentMonitoringSettings(monitor: monitor)
            case .history:
                AgentHistoryView(monitor: monitor, filter: $historyFilter)
            }
        }
        .navigationTitle("Monitoramento de agentes")
        .onChange(of: monitor.presentedEvent?.id, initial: true) {
            if monitor.presentedEvent != nil { panel = .history }
        }
        .sheet(item: $monitor.presentedEvent) { event in
            AgentEventDetail(event: event)
        }
    }
}

private struct AgentMonitoringSettings: View {
    let monitor: AgentMonitor

    var body: some View {
        Form {
            AgentMonitoringControls(monitor: monitor)
            AgentConnectionSection(monitor: monitor)
            AgentNotificationSection(monitor: monitor)
        }
        .formStyle(.grouped)
    }
}

private struct AgentMonitoringControls: View {
    let monitor: AgentMonitor

    var body: some View {
        Section {
            Toggle("Monitoramento de agentes", isOn: Binding(get: { monitor.enabled }, set: monitor.setEnabled))
            if let error = monitor.bridgeError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            if let error = monitor.persistenceError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        } footer: {
            Text("Receba avisos e controle as operações dos agentes conectados. O monitor continua ativo com a janela fechada enquanto o SimBuddy estiver em execução.")
        }
    }
}

private struct AgentConnectionSection: View {
    let monitor: AgentMonitor
    @State private var showsConfiguration = false

    var body: some View {
        Section("Conexões MCP") {
            HStack {
                Text("\(monitor.sessions.count) conexões")
                Spacer()
                Button("Configurar MCP…") { showsConfiguration = true }
            }
            ForEach(monitor.sessions) { session in
                LabeledContent(session.clientName, value: String(session.id.uuidString.prefix(8)))
            }
        }
        .sheet(isPresented: $showsConfiguration) {
            MCPConfigurationView()
        }
    }
}

private struct MCPConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    private var configuration: String {
        let path = Bundle.main.bundleURL.appending(path: "Contents/MacOS/simbuddy-mcp").path
        let object = ["mcpServers": ["simbuddy": ["command": path]]]
        let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return data.map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Conectar um agente").font(.title2.bold())
            Text("Adicione este servidor stdio nas configurações MCP do seu agente. O formato de configuração pode variar entre clientes.")
            Text(configuration)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: .rect(cornerRadius: 8))
            Text("Mantenha o SimBuddy aberto e o monitoramento ativado. Oriente o agente a usar as ferramentas do SimBuddy para operar simuladores.")
            Text("Os nomes das conexões são informados pelos clientes e não representam uma identidade verificada.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Copiar configuração") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(configuration, forType: .string)
                }
                Spacer()
                Button("Concluído") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 540)
    }
}

private struct AgentNotificationSection: View {
    let monitor: AgentMonitor

    var body: some View {
        Section {
            HStack {
                Text(monitor.notificationStatus == .authorized ? "Notificações permitidas" : monitor.notificationStatus == .denied ? "Notificações não permitidas" : "Permissão ainda não solicitada")
                Spacer()
                Menu("Categorias") {
                    ForEach(AgentCategory.allCases) { category in
                        Toggle(category.title, isOn: Binding(
                            get: { !monitor.settings.mutedCategories.contains(category) },
                            set: { monitor.setNotifications($0, category: category) }
                        ))
                    }
                }
                if monitor.notificationStatus == .denied {
                    Button("Ajustes do Sistema") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
                    }
                }
            }
        } header: {
            Text("Notificações")
        } footer: {
            Text("Eventos próximos são agrupados em 3 segundos. Bloqueios e falhas geram avisos imediatos. O histórico funciona mesmo sem permissão para notificações.")
        }
    }
}

private struct AgentHistoryFilter: Equatable {
    var simulatorID = ""
    var sessionID = ""
    var category = ""
    var outcome = ""
}

private struct AgentHistoryView: View {
    let monitor: AgentMonitor
    @Binding var filter: AgentHistoryFilter
    @State private var visibleEvents: [AgentEvent] = []

    private var devices: [String: String] {
        Dictionary(monitor.events.flatMap { event in zip(event.deviceIDs, event.deviceNames).map { ($0, $1) } }, uniquingKeysWith: { _, new in new })
    }
    private var clients: [String: String] {
        Dictionary(monitor.events.compactMap { event in event.sessionID.map { ($0.uuidString, event.clientName ?? "MCP") } }, uniquingKeysWith: { _, new in new })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Histórico de atividades").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("Simulador")
                    Picker("Simulador", selection: $filter.simulatorID) {
                        Text("Todos").tag("")
                        ForEach(devices.keys.sorted(), id: \.self) { id in Text(devices[id] ?? id).tag(id) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Sessão")
                    Picker("Sessão", selection: $filter.sessionID) {
                        Text("Todas").tag("")
                        Text("Origem desconhecida").tag("external")
                        ForEach(clients.keys.sorted(), id: \.self) { id in Text("\(clients[id] ?? "MCP") · \(id.prefix(8))").tag(id) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                GridRow {
                    Text("Categoria")
                    Picker("Categoria", selection: $filter.category) {
                        Text("Todas").tag("")
                        ForEach(AgentCategory.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Resultado")
                    Picker("Resultado", selection: $filter.outcome) {
                        Text("Todos").tag("")
                        ForEach(AgentOutcome.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            List(visibleEvents) { event in
                Button { monitor.presentedEvent = event } label: { AgentEventRow(event: event) }
                    .buttonStyle(.plain)
            }
            .overlay {
                if visibleEvents.isEmpty {
                    ContentUnavailableView("Nenhuma atividade", systemImage: "clock", description: Text("As operações dos agentes e as mudanças externas observáveis aparecerão aqui."))
                }
            }
        }
        .padding(16)
        .onChange(of: monitor.events, initial: true) { rebuild() }
        .onChange(of: filter) { rebuild() }
    }

    private func rebuild() {
        visibleEvents = monitor.events.reversed().filter {
            (filter.simulatorID.isEmpty || $0.deviceIDs.contains(filter.simulatorID)) &&
            (filter.sessionID.isEmpty || ($0.sessionID?.uuidString ?? "external") == filter.sessionID) &&
            (filter.category.isEmpty || $0.category.rawValue == filter.category) &&
            (filter.outcome.isEmpty || $0.outcome.rawValue == filter.outcome)
        }
    }
}

private struct AgentEventRow: View {
    let event: AgentEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.outcome == .blocked ? "lock.shield" : event.outcome == .failed ? "exclamationmark.triangle" : "clock")
                .foregroundStyle(event.outcome == .blocked || event.outcome == .failed ? .orange : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(event.operationTitle) · \(event.outcome.title)")
                Text(event.deviceNames.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
                Text(event.clientName ?? String(localized: "Origem desconhecida"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(event.date, format: .dateTime.hour().minute().second())
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .padding(.vertical, 3)
    }
}

private struct AgentEventDetail: View {
    let event: AgentEvent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(event.operationTitle).font(.title2.bold())
            LabeledContent("Resultado", value: event.outcome.title)
            LabeledContent("Categoria", value: event.category.title)
            LabeledContent("Simuladores", value: event.deviceNames.joined(separator: ", "))
            LabeledContent("Origem", value: event.clientName ?? String(localized: "Origem desconhecida"))
            if let sessionID = event.sessionID { LabeledContent("Sessão", value: sessionID.uuidString) }
            LabeledContent("Data") { Text(event.date, format: .dateTime.day().month().year().hour().minute().second()) }
            if let detail = event.detailText { LabeledContent("Detalhe", value: detail) }
            if let operationID = event.operationID { LabeledContent("Operação", value: operationID.uuidString) }
            Button("Concluído") { dismiss() }.keyboardShortcut(.defaultAction)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .textSelection(.enabled)
        .padding(24)
        .frame(width: 600)
    }
}

#Preview("Monitoramento") {
    AgentMonitoringView(monitor: AgentMonitor(
        persistence: AgentPersistence(directory: URL.temporaryDirectory.appending(path: "SimBuddyAgentPreview")),
        notificationsEnabled: false
    ))
    .frame(width: 720, height: 740)
}

#Preview("Histórico") {
    AgentMonitoringView(monitor: AgentMonitor(
        persistence: AgentPersistence(directory: URL.temporaryDirectory.appending(path: "SimBuddyAgentPreview")),
        notificationsEnabled: false
    ), initialPanel: .history)
    .frame(width: 720, height: 540)
}
