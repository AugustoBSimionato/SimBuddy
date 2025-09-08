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
    
    @Published var refreshOnNewDevice: Bool = true
    @Published var lastRefreshTime: Date?
    
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
    
    private var deviceMonitorTimer: Timer?
    private var previousDeviceCount: Int = 0
    private var previousDeviceUDIDs: Set<String> = []
    private var previousDeviceStatuses: [String: String] = [:]
    
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
            self.updateDeviceStatuses(parsed)
        }
    }
    
    func bootDevice(_ udid: String) {
        statusMessage = "🔄 Starting simulator..."
        
        let result = Shell.bootDevice(udid: udid)
        
        if result.exitCode == 0 {
            statusMessage = "✅ Simulator started successfully"
            // Refresh devices after a short delay to see the status change
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.refreshAllDevices()
                self.refreshBootedDevices()
            }
        } else {
            // More specific error messages
            if result.output.contains("Unable to boot device in current state") {
                statusMessage = "ℹ️ Simulator already running"
            } else if result.output.contains("No such file or directory") {
                statusMessage = "❌ Simulator not found"
            } else {
                statusMessage = "❌ Failed to start: \(result.output)"
            }
        }
        
        // Clear status message after a few seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if self.statusMessage.contains("Simulator started") ||
                self.statusMessage.contains("already running") {
                self.statusMessage = ""
            }
        }
    }
    
    func shutdownDevice(_ udid: String) {
        let result = Shell.shutdownDevice(udid: udid)
        
        if result.exitCode == 0 {
            statusMessage = "✅ Simulator shutdown successfully"
            // Refresh devices after shutdown
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.refreshAllDevices()
                self.refreshBootedDevices()
            }
        } else {
            statusMessage = "❌ Failed to shutdown: \(result.output)"
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
        
        if !newBootedDevices.isEmpty || !statusChanges.isEmpty {
            DispatchQueue.main.async {
                if !newBootedDevices.isEmpty {
                    self.refreshBootedDevices()
                    self.statusMessage = "🔄 Detected \(newBootedDevices.count) new simulator(s)"
                }
                
                if !statusChanges.isEmpty {
                    self.allDevices = parsedAll
                    self.updateDeviceStatuses(parsedAll)
                    
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
        
        if result.exitCode == 0 {
            let target = applyToAllBooted ? "all booted simulators" : "\(selectedUDIDs.count) selected simulator(s)"
            statusMessage = "✅ Cleared from \(target)"
        } else {
            statusMessage = "❌ Failed to clear: \(result.output)"
        }
    }
}
