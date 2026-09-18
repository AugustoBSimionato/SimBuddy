//
//  StatusBarOverrides.swift
//  SimBuddy
//
//  Created by Augusto Simionato on 16/08/25.
//

import Foundation

nonisolated struct StatusBarOverrides: Equatable, Sendable {
    var overridesTime = true
    var time = "9:41"

    var overridesBatteryState = true
    var batteryState: BatteryState = .discharging

    var overridesBatteryLevel = true
    var batteryLevel: Double = 100

    var overridesWiFi = true
    var wifiMode: WiFiMode = .active
    var wifiBars = 3

    var overridesCellular = true
    var cellularMode: CellularMode = .active
    var cellularBars = 4

    var overridesDataNetwork = true
    var dataNetwork: DataNetwork = .wifi

    var overridesOperatorName = true
    var operatorName = "SimBuddy"

    static let classic: StatusBarOverrides = {
        var overrides = StatusBarOverrides()
        overrides.overridesOperatorName = false
        return overrides
    }()

    var arguments: [String] {
        var arguments: [String] = []
        let trimmedTime = time.trimmingCharacters(in: .whitespaces)
        if overridesTime, !trimmedTime.isEmpty {
            arguments += ["--time", trimmedTime]
        }
        if overridesBatteryState {
            arguments += ["--batteryState", batteryState.rawValue]
        }
        if overridesBatteryLevel {
            arguments += ["--batteryLevel", "\(Int(batteryLevel.rounded()))"]
        }
        if overridesWiFi {
            arguments += ["--wifiMode", wifiMode.rawValue, "--wifiBars", "\(wifiBars)"]
        }
        if overridesCellular {
            arguments += ["--cellularMode", cellularMode.rawValue, "--cellularBars", "\(cellularBars)"]
        }
        if overridesDataNetwork {
            arguments += ["--dataNetwork", dataNetwork.rawValue]
        }
        if overridesOperatorName, !operatorName.isEmpty {
            arguments += ["--operatorName", operatorName]
        }
        return arguments
    }
}

nonisolated enum BatteryState: String, CaseIterable, Identifiable, Sendable {
    case charging, charged, discharging

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .charging: "Carregando"
        case .charged: "Carregada"
        case .discharging: "Descarregando"
        }
    }
}

nonisolated enum WiFiMode: String, CaseIterable, Identifiable, Sendable {
    case active, searching, failed

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .active: "Ativo"
        case .searching: "Procurando"
        case .failed: "Falha"
        }
    }
}

nonisolated enum CellularMode: String, CaseIterable, Identifiable, Sendable {
    case active, searching, failed, notSupported

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .active: "Ativo"
        case .searching: "Procurando"
        case .failed: "Falha"
        case .notSupported: "Sem suporte"
        }
    }
}

nonisolated enum DataNetwork: String, CaseIterable, Identifiable, Sendable {
    case wifi
    case threeG = "3g"
    case fourG = "4g"
    case lte
    case lteA = "lte-a"
    case ltePlus = "lte+"
    case fiveG = "5g"
    case fiveGPlus = "5g+"
    case fiveGUWB = "5g-uwb"
    case fiveGUC = "5g-uc"
    case hide

    var id: Self { self }

    static let cellularCases: [DataNetwork] = [.threeG, .fourG, .lte, .lteA, .ltePlus, .fiveG, .fiveGPlus, .fiveGUWB, .fiveGUC]

    var badge: String? {
        switch self {
        case .wifi, .hide: nil
        case .threeG: "3G"
        case .fourG: "4G"
        case .lte: "LTE"
        case .lteA: "LTE-A"
        case .ltePlus: "LTE+"
        case .fiveG: "5G"
        case .fiveGPlus: "5G+"
        case .fiveGUWB: "5G UW"
        case .fiveGUC: "5G UC"
        }
    }
}
