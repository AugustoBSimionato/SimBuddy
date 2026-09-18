//
//  StatusBarPreview.swift
//  SimBuddy
//
//  Created by Augusto Simionato on 11/09/26.
//

import SwiftUI

struct StatusBarPreview: View {
    let overrides: StatusBarOverrides

    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: displayedTime)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .dimmed(!overrides.overridesTime)
                .frame(maxWidth: .infinity)

            Capsule()
                .fill(.black)
                .frame(width: 96, height: 28)

            HStack(spacing: 5) {
                cellular
                network
                BatteryGlyph(level: overrides.batteryLevel / 100, state: overrides.batteryState)
                    .dimmed(!overrides.overridesBatteryLevel && !overrides.overridesBatteryState)
            }
            .font(.system(size: 13, weight: .semibold))
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: 380, minHeight: 36)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pré-visualização da barra de status")
    }

    private var displayedTime: String {
        let time = overrides.time.trimmingCharacters(in: .whitespaces)
        return time.isEmpty ? "9:41" : time
    }

    @ViewBuilder
    private var cellular: some View {
        if overrides.cellularMode != .notSupported {
            Image(
                systemName: "cellularbars",
                variableValue: overrides.cellularMode == .active ? Double(overrides.cellularBars) / 4 : 0
            )
            .dimmed(!overrides.overridesCellular)
        }
    }

    @ViewBuilder
    private var network: some View {
        if let badge = overrides.dataNetwork.badge {
            Text(verbatim: badge)
                .dimmed(!overrides.overridesDataNetwork)
        } else if overrides.dataNetwork == .wifi {
            Image(
                systemName: overrides.wifiMode == .failed ? "wifi.exclamationmark" : "wifi",
                variableValue: overrides.wifiMode == .active ? Double(overrides.wifiBars) / 3 : 0
            )
            .dimmed(!overrides.overridesWiFi)
        }
    }
}

private struct BatteryGlyph: View {
    let level: Double
    let state: BatteryState

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(.primary.opacity(0.35), lineWidth: 1)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(fill)
                    .frame(width: max(0, 21 * level))
                    .padding(2)

                if state != .discharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8, weight: .black))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: 25, height: 12)

            Capsule()
                .fill(.primary.opacity(0.35))
                .frame(width: 1.5, height: 4)
        }
    }

    private var fill: Color {
        if state != .discharging { return .green }
        return level <= 0.2 ? .red : .primary
    }
}

private extension View {
    func dimmed(_ isDimmed: Bool) -> some View {
        opacity(isDimmed ? 0.3 : 1)
    }
}
