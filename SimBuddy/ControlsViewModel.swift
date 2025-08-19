//
//  ControlsViewModel.swift
//  SimBuddy
//
//  Created by Augusto Simionato on 16/08/25.
//

import Foundation
import Combine

final class ControlsViewModel: ObservableObject {
    @Published var bootedDevices: [Device] = []
    @Published var allDevices: [Device] = []
    @Published var selectedUDIDs = Set<String>()
    @Published var applyToAllBooted: Bool = true
    
    // Refresh settings
    @Published var refreshOnNewDevice: Bool = true
    @Published var lastRefreshTime: Date?
    
    // Controls
    @Published var setTime = true
    @Published var time: String = "9:41"
    
    @Published var setBatteryState = true
    @Published var batteryState: String = "discharging"
    
    @Published var setBatteryLevel = true
    @Published var batteryLevel: Double = 100
    
    @Published var setWifi = true
    @Published var wifiMode: String = "active"
    @Published var wifiBars: Int = 3
    
    @Published var setCellular = true
    @Published var cellularMode: String = "active"
    @Published var cellularBars: Int = 4
    
    @Published var setDataNetwork = true
    @Published var dataNetwork: String = "wifi"
    
    @Published var setOperatorName = true
    @Published var operatorName: String = "SimBuddy"
    
    @Published var statusMessage: String = ""
    
    // Private properties for device monitoring
    private var deviceMonitorTimer: Timer?
    private var previousDeviceCount: Int = 0
    private var previousDeviceUDIDs: Set<String> = []
    // Novo: armazenar o status anterior dos dispositivos para detectar mudanças
    private var previousDeviceStatuses: [String: String] = [:]
    
    // Computed property for formatted last refresh time
    var lastRefreshTimeFormatted: String {
        guard let lastRefreshTime = lastRefreshTime else { return "Never" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: lastRefreshTime)
    }
    
    deinit {
        stopDeviceMonitoring()
    }
    
    func toggleDeviceSelection(_ udid: String) {
        if selectedUDIDs.contains(udid) {
            selectedUDIDs.remove(udid)
        } else {
            selectedUDIDs.insert(udid)
        }
    }
    
    func refreshBootedDevices() {
        let output = Shell.listDevices()
        print("Raw simctl output:")
        print(output)
        print("---")
        
        let parsed = DeviceParser.parseBooted(from: output)
        print("Parsed devices: \(parsed)")
        
        DispatchQueue.main.async {
            self.bootedDevices = parsed
            self.selectedUDIDs = Set(self.selectedUDIDs.filter { id in parsed.map(\.udid).contains(id) })
            self.lastRefreshTime = Date()
            
            // Update device tracking for new device detection
            self.previousDeviceCount = parsed.count
            self.previousDeviceUDIDs = Set(parsed.map(\.udid))
        }
    }

    func refreshAllDevices() {
        let output = Shell.listDevices()
        print("Raw simctl output for all devices:")
        print(output)
        print("---")
        
        let parsed = DeviceParser.parseAll(from: output)
        print("Parsed all devices: \(parsed)")
        
        DispatchQueue.main.async {
            self.allDevices = parsed
            // Atualizar o dicionário de status dos dispositivos
            self.updateDeviceStatuses(parsed)
        }
    }
    
    // MARK: - Device Status Tracking
    
    private func updateDeviceStatuses(_ devices: [Device]) {
        for device in devices {
            previousDeviceStatuses[device.udid] = device.status
        }
    }
    
    // MARK: - Device Monitoring Logic
    
    func startDeviceMonitoringIfNeeded() {
        if refreshOnNewDevice {
            startDeviceMonitoring()
        }
    }
    
    private func startDeviceMonitoring() {
        guard refreshOnNewDevice else { return }
        
        deviceMonitorTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.checkForDeviceChanges()
        }
    }
    
    func stopDeviceMonitoring() {
        deviceMonitorTimer?.invalidate()
        deviceMonitorTimer = nil
    }
    
    private func checkForDeviceChanges() {
        let output = Shell.listDevices()
        let parsedBooted = DeviceParser.parseBooted(from: output)
        let parsedAll = DeviceParser.parseAll(from: output)
        
        let currentUDIDs = Set(parsedBooted.map(\.udid))
        
        // Check if there are new booted devices
        let newBootedDevices = currentUDIDs.subtracting(previousDeviceUDIDs)
        
        // Check for status changes in all devices
        var statusChanges: [String: (old: String?, new: String?)] = [:]
        for device in parsedAll {
            let oldStatus = previousDeviceStatuses[device.udid]
            let newStatus = device.status
            
            if oldStatus != newStatus {
                statusChanges[device.udid] = (old: oldStatus, new: newStatus)
            }
        }
        
        // Update UI if there are changes
        if !newBootedDevices.isEmpty || !statusChanges.isEmpty {
            DispatchQueue.main.async {
                // Update booted devices if there are new ones
                if !newBootedDevices.isEmpty {
                    self.refreshBootedDevices()
                    self.statusMessage = "🔄 Detected \(newBootedDevices.count) new simulator(s)"
                }
                
                // Always update all devices list if there are status changes
                if !statusChanges.isEmpty {
                    self.allDevices = parsedAll
                    self.updateDeviceStatuses(parsedAll)
                    
                    // Create a more informative status message for status changes
                    if newBootedDevices.isEmpty {
                        let bootedChanges = statusChanges.filter { $0.value.new?.lowercased() == "booted" }
                        let shutdownChanges = statusChanges.filter { $0.value.new?.lowercased() == "shutdown" }
                        
                        var messages: [String] = []
                        if !bootedChanges.isEmpty {
                            messages.append("🟢 \(bootedChanges.count) booted")
                        }
                        if !shutdownChanges.isEmpty {
                            messages.append("🔴 \(shutdownChanges.count) shutdown")
                        }
                        
                        if !messages.isEmpty {
                            self.statusMessage = "📱 Status changes: \(messages.joined(separator: ", "))"
                        }
                    }
                }
                
                // Clear the message after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if self.statusMessage.contains("new simulator") || self.statusMessage.contains("Status changes") {
                        self.statusMessage = ""
                    }
                }
            }
        }
    }
    
    // MARK: - Existing Methods
    
    func buildOptions() -> [String] {
        var args: [String] = []
        if setTime, !time.trimmingCharacters(in: .whitespaces).isEmpty {
            args += ["--time", time]
        }
        if setBatteryState { args += ["--batteryState", batteryState] }
        if setBatteryLevel { args += ["--batteryLevel", "\(Int(batteryLevel))"] }
        if setWifi {
            args += ["--wifiMode", wifiMode, "--wifiBars", "\(wifiBars)"]
        }
        if setCellular {
            args += ["--cellularMode", cellularMode, "--cellularBars", "\(cellularBars)"]
        }
        if setDataNetwork { args += ["--dataNetwork", dataNetwork] }
        if setOperatorName, !operatorName.isEmpty { args += ["--operatorName", operatorName] }
        return args
    }
    
    func applyOverrides() {
        let options = buildOptions()
        if options.isEmpty {
            statusMessage = "Nothing to apply."
            return
        }
        
        if !applyToAllBooted && selectedUDIDs.isEmpty {
            statusMessage = "Please select at least one simulator."
            return
        }
        
        let result: Shell.Result
        if applyToAllBooted {
            result = Shell.runSimctlStatusBarAllBootedOverride(options: options)
        } else {
            result = Shell.runSimctlStatusBarSelectedOverride(udids: Array(selectedUDIDs), options: options)
        }
        
        // User-friendly status messages
        if result.exitCode == 0 {
            let target = applyToAllBooted ? "all booted simulators" : "\(selectedUDIDs.count) selected simulator(s)"
            statusMessage = "✅ Applied to \(target)"
        } else {
            statusMessage = "❌ Failed to apply: \(result.output)"
        }
    }
    
    func clearOverrides() {
        if !applyToAllBooted && selectedUDIDs.isEmpty {
            statusMessage = "Please select at least one simulator."
            return
        }
        
        let result: Shell.Result
        if applyToAllBooted {
            result = Shell.clearStatusBarAllBooted()
        } else {
            result = Shell.clearStatusBarSelected(udids: Array(selectedUDIDs))
        }
        
        // User-friendly status messages
        if result.exitCode == 0 {
            let target = applyToAllBooted ? "all booted simulators" : "\(selectedUDIDs.count) selected simulator(s)"
            statusMessage = "✅ Cleared from \(target)"
        } else {
            statusMessage = "❌ Failed to clear: \(result.output)"
        }
    }
}
