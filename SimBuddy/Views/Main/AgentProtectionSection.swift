import AgentCore
import SwiftUI

struct AgentProtectionSection: View {
    let monitor: AgentMonitor
    let simulatorID: String

    var body: some View {
        Section {
            Toggle("Proteger de agentes", isOn: Binding(
                get: { monitor.protection(for: simulatorID).enabled },
                set: { value in
                    var protection = monitor.protection(for: simulatorID)
                    protection.enabled = value
                    monitor.setProtection(protection, for: simulatorID)
                }
            ))
            if monitor.protection(for: simulatorID).enabled {
                ForEach(AgentCategory.allCases) { category in
                    Toggle(isOn: Binding(
                        get: { monitor.protection(for: simulatorID).permits(category) },
                        set: { allowed in
                            var protection = monitor.protection(for: simulatorID)
                            if allowed { protection.blocked.remove(category) } else { protection.blocked.insert(category) }
                            monitor.setProtection(protection, for: simulatorID)
                        }
                    )) {
                        Text("Permitir: \(category.title)")
                    }
                }
            }
        } header: {
            Label("Proteção contra agentes", systemImage: "lock.shield")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("As regras ficam salvas para este simulador e se aplicam às operações feitas pelo MCP do SimBuddy.")
                Text("Comandos diretos do terminal, Xcode ou outros conectores ficam fora desses bloqueios.")
                if monitor.protection(for: simulatorID).enabled {
                    Text("Ao permitir testes, o Xcode e os scripts do projeto podem modificar ou reiniciar o simulador internamente.")
                }
                if !monitor.enabled {
                    Text("Ative o monitoramento de agentes para usar a integração MCP.")
                }
            }
        }
    }
}
