//
//  ContentView.swift
//  SimBuddy
//
//  Created by Augusto Simionato on 16/08/25.
//

import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "📱"
        statusItem.button?.action = #selector(toggleMenu(_:))
        statusItem.button?.target = self
    }
    
    @objc private func toggleMenu(_ sender: Any?) {
        let menu = NSMenu()
        
        menu.addItem(withTitle: "Apply Preset (9:41, 100%, full bars)", action: #selector(applyPreset), keyEquivalent: "")
        menu.addItem(withTitle: "Clear Overrides", action: #selector(clearOverrides), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Controls…", action: #selector(openControls), keyEquivalent: "")
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
    
    @objc private func applyPreset() {
        _ = Shell.runSimctlStatusBarAllBootedOverride(options: [
            "--time", "9:41",
            "--dataNetwork", "wifi",
            "--wifiMode", "active",
            "--wifiBars", "3",
            "--cellularMode", "active",
            "--cellularBars", "4",
            "--batteryState", "charged",
            "--batteryLevel", "100"
        ])
    }
    
    @objc private func clearOverrides() {
        _ = Shell.clearStatusBarAllBooted()
    }
    
    @objc private func openControls() {
        for w in NSApp.windows {
            if let title = w.title as String?, title.contains("Simulator Status Controls") {
                w.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
    }
    
    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

struct ControlsView: View {
    @StateObject private var vm = ControlsViewModel()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Booted Simulators")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button("Refresh") { vm.refreshBootedDevices() }
                    Spacer()
                    Toggle("Apply to all booted", isOn: $vm.applyToAllBooted)
                        .toggleStyle(SwitchToggleStyle())
                        .help("When on, applies to 'booted' (all running simulators); otherwise, only to selected UDIDs.")
                }
                
                // Refresh Settings
                HStack {
                    Toggle("Refresh on new simulator detected", isOn: $vm.refreshOnNewDevice)
                        .toggleStyle(SwitchToggleStyle())
                        .help("Automatically refresh when a new simulator is detected")
                    
                    Spacer()
                    
                    if vm.lastRefreshTime != nil {
                        Text("Last updated: \(vm.lastRefreshTimeFormatted)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .font(.caption)
            }
            
            // Custom selectable list instead of List with selection
            if vm.bootedDevices.isEmpty {
                Text("No booted simulators found")
                    .foregroundColor(.secondary)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 0) {
                    // Header showing selection info when not applying to all
                    if !vm.applyToAllBooted {
                        HStack {
                            Text("Select simulators to apply overrides to:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(vm.selectedUDIDs.count) selected")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(NSColor.controlBackgroundColor))
                    }
                    
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(vm.bootedDevices, id: \.udid) { device in
                                DeviceRow(
                                    device: device,
                                    isSelected: vm.selectedUDIDs.contains(device.udid),
                                    isSelectable: !vm.applyToAllBooted,
                                    onToggle: { vm.toggleDeviceSelection(device.udid) }
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .frame(height: 150)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            }
            
            Divider()
            
            Text("Overrides")
                .font(.headline)
            
            Form {
                HStack {
                    Text("Time")
                    TextField("e.g. 9:41 or 15:42", text: $vm.time)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .focusable(false)
                    Toggle("Set", isOn: $vm.setTime)
                }
                
                HStack {
                    Text("Battery State")
                    Picker("", selection: $vm.batteryState) {
                        Text("charged").tag("charged")
                        Text("charging").tag("charging")
                        Text("discharging").tag("discharging")
                    }.frame(width: 160)
                    Toggle("Set", isOn: $vm.setBatteryState)
                    
                    Text("Battery Level")
                    Slider(value: $vm.batteryLevel, in: 0...100, step: 1)
                        .frame(width: 180)
                    Text("\(Int(vm.batteryLevel))%")
                    Toggle("Set", isOn: $vm.setBatteryLevel)
                }
                
                HStack {
                    Text("Wi‑Fi")
                    Picker("Mode", selection: $vm.wifiMode) {
                        Text("active").tag("active")
                        Text("failed").tag("failed")
                        Text("searching").tag("searching")
                    }.frame(width: 130)
                    Picker("Bars", selection: $vm.wifiBars) {
                        ForEach(0..<4) { Text("\($0)").tag($0) }
                    }.frame(width: 80)
                    Toggle("Set", isOn: $vm.setWifi)
                }
                
                HStack {
                    Text("Cellular")
                    Picker("Mode", selection: $vm.cellularMode) {
                        Text("active").tag("active")
                        Text("searching").tag("searching")
                        Text("failed").tag("failed")
                    }.frame(width: 130)
                    Picker("Bars", selection: $vm.cellularBars) {
                        ForEach(0..<5) { Text("\($0)").tag($0) }
                    }.frame(width: 80)
                    Toggle("Set", isOn: $vm.setCellular)
                }
                
                HStack {
                    Text("Data Network")
                    Picker("", selection: $vm.dataNetwork) {
                        Text("wifi").tag("wifi")
                        Text("lte").tag("lte")
                        Text("4g").tag("4g")
                        Text("3g").tag("3g")
                        Text("edge").tag("edge")
                    }.frame(width: 160)
                    Toggle("Set", isOn: $vm.setDataNetwork)
                }
                
                HStack {
                    Text("Operator")
                    TextField("Carrier name", text: $vm.operatorName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .focusable(false)
                    Toggle("Set", isOn: $vm.setOperatorName)
                }
            }
            
            HStack {
                Button("Apply Overrides") { 
                    vm.applyOverrides() 
                }
                .disabled(!vm.applyToAllBooted && vm.selectedUDIDs.isEmpty)
                
                Button("Clear Overrides") { 
                    vm.clearOverrides() 
                }
                .disabled(!vm.applyToAllBooted && vm.selectedUDIDs.isEmpty)
                
                Spacer()
                Text(vm.statusMessage)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
        .padding(16)
        .onAppear { 
            vm.refreshBootedDevices()
            vm.startDeviceMonitoringIfNeeded()
        }
        .onDisappear {
            vm.stopDeviceMonitoring()
        }
    }
}

// Custom row component for device selection
struct DeviceRow: View {
    let device: Device
    let isSelected: Bool
    let isSelectable: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            if isSelectable {
                Button(action: onToggle) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundColor(isSelected ? .blue : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Device icon
            Image(systemName: device.iconName)
                .foregroundColor(.blue)
                .frame(width: 16, height: 16)
            
            HStack {
                Text(device.name)
                Spacer()
                Text(device.runtime)
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text(device.udid.short)
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isSelectable {
                    onToggle()
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Rectangle()
                .fill(isSelected && isSelectable ? Color.blue.opacity(0.1) : Color.clear)
        )
        .opacity(isSelectable ? 1.0 : 0.7)
    }
}

final class ControlsViewModel: ObservableObject {
    @Published var bootedDevices: [Device] = []
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
    
    @Published var setOperatorName = false
    @Published var operatorName: String = "Carrier"
    
    @Published var statusMessage: String = ""
    
    // Private properties for device monitoring
    private var deviceMonitorTimer: Timer?
    private var previousDeviceCount: Int = 0
    private var previousDeviceUDIDs: Set<String> = []
    
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
    
    // MARK: - Device Monitoring Logic
    
    func startDeviceMonitoringIfNeeded() {
        if refreshOnNewDevice {
            startDeviceMonitoring()
        }
    }
    
    private func startDeviceMonitoring() {
        guard refreshOnNewDevice else { return }
        
        deviceMonitorTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.checkForNewDevices()
        }
    }
    
    func stopDeviceMonitoring() {
        deviceMonitorTimer?.invalidate()
        deviceMonitorTimer = nil
    }
    
    private func checkForNewDevices() {
        let output = Shell.listDevices()
        let parsed = DeviceParser.parseBooted(from: output)
        let currentUDIDs = Set(parsed.map(\.udid))
        
        // Check if there are new devices (devices that weren't in the previous set)
        let newDevices = currentUDIDs.subtracting(previousDeviceUDIDs)
        
        if !newDevices.isEmpty {
            DispatchQueue.main.async {
                self.refreshBootedDevices()
                self.statusMessage = "🔄 Detected \(newDevices.count) new simulator(s)"
                
                // Clear the message after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if self.statusMessage.contains("new simulator") {
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

// MARK: - Shell helpers

enum Shell {
    struct Result {
        let exitCode: Int32
        let output: String
    }
    
    @discardableResult
    static func run(_ executable: String, _ args: [String]) -> Result {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = args
        
        let out = Pipe()
        let err = Pipe()
        task.standardOutput = out
        task.standardError = err
        
        do {
            try task.run()
            task.waitUntilExit()
            let dataOut = out.fileHandleForReading.readDataToEndOfFile()
            let dataErr = err.fileHandleForReading.readDataToEndOfFile()
            let joined = [String(data: dataOut, encoding: .utf8), String(data: dataErr, encoding: .utf8)]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            return Result(exitCode: task.terminationStatus, output: joined)
        } catch {
            return Result(exitCode: -1, output: "Error: \(error.localizedDescription)")
        }
    }
    
    static func listDevices() -> String {
        run("/usr/bin/xcrun", ["simctl", "list", "devices"]).output
    }
    
    static func runSimctlStatusBarAllBootedOverride(options: [String]) -> Result {
        var args = ["simctl", "status_bar", "booted", "override"]
        args.append(contentsOf: options)
        return run("/usr/bin/xcrun", args)
    }
    
    static func runSimctlStatusBarSelectedOverride(udids: [String], options: [String]) -> Result {
        var combined = ""
        var lastExit: Int32 = 0
        for udid in udids {
            var args = ["simctl", "status_bar", udid, "override"]
            args.append(contentsOf: options)
            let r = run("/usr/bin/xcrun", args)
            combined += "[\(udid.short)] \(r.output)\n"
            lastExit = r.exitCode
        }
        return Result(exitCode: lastExit, output: combined)
    }
    
    static func clearStatusBarAllBooted() -> Result {
        run("/usr/bin/xcrun", ["simctl", "status_bar", "booted", "clear"])
    }
    
    static func clearStatusBarSelected(udids: [String]) -> Result {
        var combined = ""
        var lastExit: Int32 = 0
        for udid in udids {
            let r = run("/usr/bin/xcrun", ["simctl", "status_bar", udid, "clear"])
            combined += "[\(udid.short)] \(r.output)\n"
            lastExit = r.exitCode
        }
        return Result(exitCode: lastExit, output: combined)
    }
}

// MARK: - Parsing devices

struct Device: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let udid: String
    let runtime: String
    
    var iconName: String {
        let lowercaseName = name.lowercased()
        
        if lowercaseName.contains("iphone") {
            return "iphone"
        } else if lowercaseName.contains("ipad") {
            return "ipad"
        } else if lowercaseName.contains("watch") {
            return "applewatch"
        } else if lowercaseName.contains("tv") {
            return "appletv"
        } else if lowercaseName.contains("vision") {
            return "visionpro"
        } else {
            return "rectangle.on.rectangle" // Generic device icon
        }
    }
}

enum DeviceParser {
    static func parseBooted(from listOutput: String) -> [Device] {
        var currentRuntime: String = ""
        var devices: [Device] = []
        
        let lines = listOutput.components(separatedBy: .newlines)
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Check for runtime section headers
            if trimmedLine.hasPrefix("--") && trimmedLine.hasSuffix("--") {
                currentRuntime = trimmedLine
                    .replacingOccurrences(of: "--", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } else if trimmedLine.contains("(Booted)") {
                // Use regex to parse device line more reliably
                let pattern = #"^(.+?)\s+\(([A-F0-9-]{36})\)\s+\(Booted\)"#
                if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                   let match = regex.firstMatch(in: trimmedLine, range: NSRange(trimmedLine.startIndex..., in: trimmedLine)) {
                    
                    if let nameRange = Range(match.range(at: 1), in: trimmedLine),
                       let udidRange = Range(match.range(at: 2), in: trimmedLine) {
                        let name = String(trimmedLine[nameRange]).trimmingCharacters(in: .whitespaces)
                        let udid = String(trimmedLine[udidRange])
                        
                        devices.append(Device(name: name, udid: udid, runtime: currentRuntime))
                    }
                }
            }
        }
        return devices
    }
}

private extension String {
    var short: String {
        if self.count <= 6 { return self }
        let prefixPart = self.prefix(4)
        let suffixPart = self.suffix(4)
        return "\(prefixPart)…\(suffixPart)"
    }
}
