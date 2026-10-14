import AgentCore
import AppKit
import UserNotifications

@MainActor
final class AgentNotifications: NSObject, UNUserNotificationCenterDelegate {
    var openEvent: ((UUID) -> Void)?
    var authorization: UNAuthorizationStatus = .notDetermined
    var authorizationChanged: ((UNAuthorizationStatus) -> Void)?
    private var batches: [String: [AgentEvent]] = [:]
    private var pending: [String: Task<Void, Never>] = [:]
    private let batchDelay: Duration
    private let delivery: (([AgentEvent]) -> Void)?

    init(batchDelay: Duration = .seconds(3), delivery: (([AgentEvent]) -> Void)? = nil) {
        self.batchDelay = batchDelay; self.delivery = delivery
    }

    func start() {
        UNUserNotificationCenter.current().delegate = self
        Task { await updateAuthorization() }
    }

    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await updateAuthorization()
    }

    func updateAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        authorizationChanged?(authorization)
    }

    func enqueue(_ event: AgentEvent) {
        guard event.outcome != .requested && event.outcome != .queued else { return }
        if [.blocked, .failed, .interrupted].contains(event.outcome) {
            deliver([event]); return
        }
        let key = event.deviceIDs.sorted().joined(separator: ",") + ":" + (event.sessionID?.uuidString ?? "external")
        batches[key, default: []].append(event)
        guard pending[key] == nil else { return }
        let delay = batchDelay
        pending[key] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            let events = batches.removeValue(forKey: key) ?? []
            pending[key] = nil
            deliver(events)
        }
    }

    func cancelPending() {
        pending.values.forEach { $0.cancel() }
        pending.removeAll(); batches.removeAll()
    }

    private func deliver(_ events: [AgentEvent]) {
        if let delivery { delivery(events); return }
        guard let last = events.last else { return }
        let content = UNMutableNotificationContent()
        content.title = last.outcome == .blocked ? String(localized: "Operação de agente bloqueada") : String(localized: "Atividade no simulador")
        let names = last.deviceNames.isEmpty ? String(localized: "Simuladores") : last.deviceNames.joined(separator: ", ")
        content.body = events.count == 1
            ? String(localized: "\(names): \(last.operationTitle) · \(last.outcome.title)")
            : String(localized: "\(names): \(events.count) eventos. Último: \(last.operationTitle) · \(last.outcome.title)")
        content.threadIdentifier = last.deviceIDs.joined(separator: ",") + (last.sessionID?.uuidString ?? "external")
        content.userInfo = ["eventID": last.id.uuidString]
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                           willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                           didReceive response: UNNotificationResponse) async {
        guard let raw = response.notification.request.content.userInfo["eventID"] as? String,
              let id = UUID(uuidString: raw) else { return }
        await MainActor.run { openEvent?(id) }
    }
}

extension AgentEvent {
    var operationTitle: String {
        switch operation {
        case "state": String(localized: "Estado alterado")
        case "available": String(localized: "Disponível na lista")
        case "unavailable": String(localized: "Indisponível na lista")
        case "unsupported": String(localized: "Operação não suportada")
        default: operation
        }
    }

    var detailText: String? {
        guard let detail else { return nil }
        if outcome == .blocked {
            if detail == "invalidInput" { return String(localized: "Operação ou parâmetros inválidos. Nenhum comando foi executado.") }
            if detail == "disabled" { return String(localized: "O monitoramento foi desativado antes da execução.") }
            return String(localized: "A proteção do simulador bloqueia esta categoria: \(category.title).")
        }
        if detail == "unavailable" { return String(localized: "Não foi possível consultar os simuladores antes da execução.") }
        if detail == "clipboardVerification" { return String(localized: "O simctl não preservou o texto no clipboard do simulador. A operação não foi confirmada.") }
        switch detail {
        case "Booted": return String(localized: "Em execução")
        case "Booting": return String(localized: "Iniciando")
        case "Shutdown": return String(localized: "Desligado")
        case "Shutting Down": return String(localized: "Encerrando")
        default: return detail
        }
    }
}

extension AgentCategory {
    var title: String {
        switch self {
        case .inspection: String(localized: "Consultas")
        case .boot: String(localized: "Iniciar simuladores")
        case .stop: String(localized: "Desligar e reiniciar")
        case .destructive: String(localized: "Excluir e apagar dados")
        case .apps: String(localized: "Instalar e executar apps")
        case .tests: String(localized: "Executar testes")
        case .capture: String(localized: "Capturas e gravações")
        case .configuration: String(localized: "Configurações do simulador")
        case .content: String(localized: "Mídia, clipboard e notificações")
        }
    }
}

extension AgentOutcome {
    var title: String {
        switch self {
        case .requested: String(localized: "Solicitada")
        case .queued: String(localized: "Na fila")
        case .started: String(localized: "Iniciada")
        case .succeeded: String(localized: "Concluída")
        case .failed: String(localized: "Falhou")
        case .blocked: String(localized: "Bloqueada")
        case .cancelled: String(localized: "Cancelada")
        case .interrupted: String(localized: "Interrompida")
        case .observed: String(localized: "Observada externamente")
        }
    }
}
