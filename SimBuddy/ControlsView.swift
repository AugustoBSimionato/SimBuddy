//
//  ContentView.swift
//  SimBuddy
//
//  Created by Augusto Simionato on 16/08/25.
//

import SwiftUI
import Combine

struct ControlsView: View {
    @StateObject private var vm = ControlsViewModel()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionCard(systemImage: "iphone.and.arrow.forward", title: "Booted Simulators") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Button(action: { vm.refreshBootedDevices() }) {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            Spacer()
                            
                            Toggle("Apply to all booted", isOn: $vm.applyToAllBooted)
                                .toggleStyle(SwitchToggleStyle())
                                .help("When on, applies to 'booted' (all running simulators); otherwise, only to selected UDIDs.")
                                .controlSize(.small)
                        }
                        
                        HStack {
                            Toggle("Refresh on new simulator detected", isOn: $vm.refreshOnNewDevice)
                                .toggleStyle(SwitchToggleStyle())
                                .help("Automatically refresh when a new simulator is detected")
                                .controlSize(.small)
                            
                            Spacer()
                            
                            if vm.lastRefreshTime != nil {
                                Text("Last updated: \(vm.lastRefreshTimeFormatted)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .font(.caption)
                        
                        if vm.bootedDevices.isEmpty {
                            VStack {
                                Text("No booted simulators found")
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 40)
                            }
                            .frame(maxWidth: .infinity)
                            .background(Color.clear)
                        } else {
                            VStack(spacing: 0) {
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
                                    .padding(.vertical, 6)
                                    .background(Color(NSColor.controlBackgroundColor))
                                }
                                
                                ScrollView {
                                    LazyVStack(spacing: 6) {
                                        ForEach(vm.bootedDevices, id: \.udid) { device in
                                            DeviceRow(
                                                device: device,
                                                isSelected: vm.selectedUDIDs.contains(device.udid),
                                                isSelectable: !vm.applyToAllBooted,
                                                onToggle: { vm.toggleDeviceSelection(device.udid) }
                                            )
                                            .animation(.default, value: vm.selectedUDIDs)
                                        }
                                    }
                                    .padding(.vertical, 6)
                                }
                                .frame(maxHeight: 220)
                            }
                            .frame(maxWidth: .infinity)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                            )
                        }
                    }
                    .padding(12)
                }
                
                SectionCard(systemImage: "slider.horizontal.3", title: "Overrides") {
                    VStack(spacing: 12) {
                        VStack(spacing: 8) {
                            HStack {
                                Text("Time")
                                    .frame(width: 80, alignment: .leading)
                                TextField("e.g. 9:41 or 15:42", text: $vm.time)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 160)
                                    .focusable(false)
                                Toggle("Set", isOn: $vm.setTime)
                                    .controlSize(.small)
                                Spacer()
                            }
                            
                            HStack(spacing: 12) {
                                Text("Battery")
                                    .frame(width: 80, alignment: .leading)
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Picker("Status", selection: $vm.batteryState) {
                                            Text("charged").tag("charged")
                                            Text("charging").tag("charging")
                                            Text("discharging").tag("discharging")
                                        }
                                        .frame(width: 170)
                                        Toggle("Set", isOn: $vm.setBatteryState)
                                            .controlSize(.small)
                                    }
                                    HStack {
                                        Text("Level")
                                        Slider(value: $vm.batteryLevel, in: 0...100, step: 5)
                                            .frame(width: 220)
                                        Text("\(Int(vm.batteryLevel))%")
                                            .frame(width: 42, alignment: .trailing)
                                        Toggle("Set", isOn: $vm.setBatteryLevel)
                                            .controlSize(.small)
                                    }
                                }
                                Spacer()
                            }
                            
                            HStack(spacing: 12) {
                                Text("Wi‑Fi")
                                    .frame(width: 80, alignment: .leading)
                                Picker("Mode", selection: $vm.wifiMode) {
                                    Text("active").tag("active")
                                    Text("failed").tag("failed")
                                    Text("searching").tag("searching")
                                }
                                .frame(width: 140)
                                Picker("Bars", selection: $vm.wifiBars) {
                                    ForEach(0..<4) { Text("\($0)").tag($0) }
                                }
                                .frame(width: 80)
                                Toggle("Set", isOn: $vm.setWifi)
                                    .controlSize(.small)
                                Spacer()
                            }
                            
                            HStack(spacing: 12) {
                                Text("Cellular")
                                    .frame(width: 80, alignment: .leading)
                                Picker("Mode", selection: $vm.cellularMode) {
                                    Text("active").tag("active")
                                    Text("searching").tag("searching")
                                    Text("failed").tag("failed")
                                }
                                .frame(width: 140)
                                Picker("Bars", selection: $vm.cellularBars) {
                                    ForEach(0..<5) { Text("\($0)").tag($0) }
                                }
                                .frame(width: 80)
                                Toggle("Set", isOn: $vm.setCellular)
                                    .controlSize(.small)
                                Spacer()
                            }
                            
                            HStack(spacing: 12) {
                                Text("Data")
                                    .frame(width: 80, alignment: .leading)
                                Picker("Type", selection: $vm.dataNetwork) {
                                    Text("wifi").tag("wifi")
                                    Text("lte").tag("lte")
                                    Text("4g").tag("4g")
                                    Text("3g").tag("3g")
                                }
                                .frame(width: 123)
                                Toggle("Set", isOn: $vm.setDataNetwork)
                                    .controlSize(.small)
                                Spacer()
                            }
                            
                            HStack {
                                Text("Operator")
                                    .frame(width: 80, alignment: .leading)
                                TextField("Carrier name", text: $vm.operatorName)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 220)
                                    .focusable(false)
                                Toggle("Set", isOn: $vm.setOperatorName)
                                    .controlSize(.small)
                                Spacer()
                            }
                        }
                        
                        HStack {
                            Button(action: { vm.applyOverrides() }) {
                                Label("Apply Overrides", systemImage: "wand.and.stars")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!vm.applyToAllBooted && vm.selectedUDIDs.isEmpty)
                            
                            Button(action: { vm.clearOverrides() }) {
                                Label("Clear Overrides", systemImage: "xmark.circle")
                            }
                            .buttonStyle(.bordered)
                            .disabled(!vm.applyToAllBooted && vm.selectedUDIDs.isEmpty)
                            
                            Spacer()
                            
                            Text(vm.statusMessage)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .font(.caption)
                        }
                    }
                    .padding(12)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            vm.refreshBootedDevices()
            vm.startDeviceMonitoringIfNeeded()
        }
        .onDisappear {
            vm.stopDeviceMonitoring()
        }
    }
}

// MARK: - SectionCard helper
private struct SectionCard<Content: View>: View {
    let systemImage: String
    let title: String
    let content: Content
    
    init(systemImage: String, title: String, @ViewBuilder content: () -> Content) {
        self.systemImage = systemImage
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.blue)
                Text(title)
                    .font(.headline)
                Spacer()
            }
            .padding([.top, .leading])
            content
        }
        .background(.regularMaterial)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor).opacity(0.6), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
    }
}

// Custom row component for device selection
struct DeviceRow: View {
    let device: Device
    let isSelected: Bool
    let isSelectable: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            if isSelectable {
                Button(action: onToggle) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .imageScale(.large)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Image(systemName: device.iconName)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundColor(.blue)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.08)))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.subheadline)
                HStack(spacing: 8) {
                    Text(device.runtime)
                        .foregroundColor(.secondary)
                        .font(.caption2)
                    Text(device.udid.short)
                        .foregroundColor(.secondary)
                        .font(.caption2)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected && isSelectable ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            if isSelectable { onToggle() }
        }
        .opacity(isSelectable ? 1.0 : 0.75)
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
            return "ipad.landscape"
        } else if lowercaseName.contains("watch") {
            return "applewatch"
        } else if lowercaseName.contains("tv") {
            return "appletv"
        } else if lowercaseName.contains("vision") {
            return "vision.pro"
        } else {
            return "apple.logo"
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
