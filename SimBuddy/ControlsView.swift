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
                HStack(spacing: 10) {
                    SectionCard(systemImage: "macbook.and.iphone", title: "Todos os simuladores") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Button(action: { vm.refreshAllDevices() }) {
                                    Label("Atualizar todos", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                
                                Spacer()
                                
                                Text("\(vm.allDevices.count) simuladores")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            if vm.allDevices.isEmpty {
                                VStack {
                                    Text("Nenhum simulador encontrado")
                                        .foregroundColor(.secondary)
                                        .padding(.vertical, 40)
                                }
                                .frame(maxWidth: .infinity, maxHeight: 300)
                                .background(Color.clear)
                            } else {
                                ScrollView(.vertical, showsIndicators: true) {
                                    LazyVStack(spacing: 6) {
                                        ForEach(vm.allDevices, id: \.udid) { device in
                                            AllDeviceRow(device: device)
                                        }
                                    }
                                    .padding(.vertical, 6)
                                }
                                .frame(maxHeight: 300)
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
                    
                    SectionCard(systemImage: "iphone.and.arrow.forward", title: "Simuladores em execução") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Button(action: { vm.refreshBootedDevices() }) {
                                    Label("Atualizar", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                
                                Spacer()
                                
                                Toggle("Aplicar a todos os simuladores em execução", isOn: $vm.applyToAllBooted)
                                    .toggleStyle(SwitchToggleStyle())
                                    .help("Quando ativado, aplica em 'booted' (todos os simuladores em execução); caso contrário, apenas aos UDIDs selecionados.")
                                    .controlSize(.small)
                            }
                            
                            HStack {
                                Toggle("Atualizar ao detectar novo simulador", isOn: $vm.refreshOnNewDevice)
                                    .toggleStyle(SwitchToggleStyle())
                                    .help("Atualiza automaticamente quando um novo simulador for detectado")
                                    .controlSize(.small)
                                
                                Spacer()
                                
                                if vm.lastRefreshTime != nil {
                                    Text("Última atualização: \(vm.lastRefreshTimeFormatted)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .font(.caption)
                            
                            if vm.bootedDevices.isEmpty {
                                VStack {
                                    Text("Nenhum simulador em execução encontrado")
                                        .foregroundColor(.secondary)
                                        .padding(.vertical, 40)
                                }
                                .frame(maxWidth: .infinity, maxHeight: 220)
                                .background(Color.clear)
                            } else {
                                VStack(spacing: 0) {
                                    if !vm.applyToAllBooted {
                                        HStack {
                                            Text("Selecione simuladores para aplicar alterações:")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text("\(vm.selectedUDIDs.count) selecionados")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .background(Color(NSColor.controlBackgroundColor))
                                    }
                                    
                                    ScrollView(.vertical, showsIndicators: true) {
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
                                    .frame(maxHeight: vm.applyToAllBooted ? 220 : 180)
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
                }
                
                SectionCard(systemImage: "slider.horizontal.3", title: "Substituições") {
                    VStack(spacing: 12) {
                        VStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Bateria")
                                    .fontWeight(.semibold)
                                HStack(spacing: 6) {
                                    HStack {
                                        Toggle("Status", isOn: $vm.setBatteryState)
                                            .controlSize(.small)
                                        Picker("", selection: $vm.batteryState) {
                                            Text("carregada").tag("charged")
                                            Text("carregando").tag("charging")
                                            Text("descarregando").tag("discharging")
                                        }
                                        .frame(width: 170)
                                    }
                                    HStack {
                                        Toggle("Nível", isOn: $vm.setBatteryLevel)
                                            .controlSize(.small)
                                        Slider(value: $vm.batteryLevel, in: 0...100, step: 5)
                                            .frame(width: 220)
                                        Text("\(Int(vm.batteryLevel))%")
                                            .frame(width: 42, alignment: .trailing)
                                    }
                                    Spacer()
                                }
                            }
                            .padding(.bottom)
                            
                            HStack {
                                Toggle("Hora", isOn: $vm.setTime)
                                    .controlSize(.small)
                                TextField("ex.: 9:41 ou 15:42", text: $vm.time)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 160)
                                    .focusable(false)
                                Spacer()
                            }
                            
                            HStack(spacing: 12) {
                                Toggle("Wi‑Fi", isOn: $vm.setWifi)
                                    .controlSize(.small)
                                Picker("Modo", selection: $vm.wifiMode) {
                                    Text("ativo").tag("active")
                                    Text("falha").tag("failed")
                                    Text("procurando").tag("searching")
                                }
                                .frame(width: 140)
                                Picker("Barras", selection: $vm.wifiBars) {
                                    ForEach(0..<4) { Text("\($0)").tag($0) }
                                }
                                .frame(width: 90)
                                Spacer()
                            }
                            
                            HStack(spacing: 12) {
                                Toggle("Celular", isOn: $vm.setCellular)
                                    .controlSize(.small)
                                Picker("Modo", selection: $vm.cellularMode) {
                                    Text("ativo").tag("active")
                                    Text("procurando").tag("searching")
                                    Text("falha").tag("failed")
                                }
                                .frame(width: 140)
                                Picker("Barras", selection: $vm.cellularBars) {
                                    ForEach(0..<5) { Text("\($0)").tag($0) }
                                }
                                .frame(width: 90)
                                Spacer()
                            }
                            
                            HStack(spacing: 12) {
                                Toggle("Dados", isOn: $vm.setDataNetwork)
                                    .controlSize(.small)
                                Picker("Tipo", selection: $vm.dataNetwork) {
                                    Text("wifi").tag("wifi")
                                    Text("lte").tag("lte")
                                    Text("4g").tag("4g")
                                    Text("3g").tag("3g")
                                }
                                .frame(width: 123)
                                Spacer()
                            }
                            
                            HStack {
                                Toggle("Operadora", isOn: $vm.setOperatorName)
                                    .controlSize(.small)
                                TextField("Nome da operadora", text: $vm.operatorName)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 220)
                                    .focusable(false)
                                Spacer()
                            }
                        }
                        .padding(.bottom)
                        
                        HStack {
                            Button(action: { vm.applyOverrides() }) {
                                Label("Aplicar alterações", systemImage: "wand.and.stars")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!vm.applyToAllBooted && vm.selectedUDIDs.isEmpty)
                            
                            Button(action: { vm.clearOverrides() }) {
                                Label("Limpar alterações", systemImage: "xmark.circle")
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
            .fontDesign(.rounded)
        }
        .onAppear {
            vm.refreshBootedDevices()
            vm.refreshAllDevices()
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

struct AllDeviceRow: View {
    let device: Device
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.iconName)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundColor(device.isBooted ? .green : .blue)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill((device.isBooted ? Color.green : Color.blue).opacity(0.08))
                )
            
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
                    if let status = device.status {
                        Text(status)
                            .foregroundColor(device.isBooted ? .green : .orange)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill((device.isBooted ? Color.green : Color.orange).opacity(0.15))
                            )
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(device.isBooted ? Color.green.opacity(0.05) : Color.clear)
        )
        .opacity(device.isBooted ? 1.0 : 0.75)
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
    let status: String?
    
    init(name: String, udid: String, runtime: String, status: String? = nil) {
        self.name = name
        self.udid = udid
        self.runtime = runtime
        self.status = status
    }
    
    var isBooted: Bool {
        return status?.lowercased() == "booted"
    }
    
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
    
    static func parseAll(from listOutput: String) -> [Device] {
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
            } else if trimmedLine.contains("(") && trimmedLine.contains(")") {
                // Parse all devices (Shutdown, Booted, etc.)
                let pattern = #"^(.+?)\s+\(([A-F0-9-]{36})\)\s+\((.+?)\)"#
                if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                   let match = regex.firstMatch(in: trimmedLine, range: NSRange(trimmedLine.startIndex..., in: trimmedLine)) {
                    
                    if let nameRange = Range(match.range(at: 1), in: trimmedLine),
                       let udidRange = Range(match.range(at: 2), in: trimmedLine),
                       let statusRange = Range(match.range(at: 3), in: trimmedLine) {
                        let name = String(trimmedLine[nameRange]).trimmingCharacters(in: .whitespaces)
                        let udid = String(trimmedLine[udidRange])
                        let status = String(trimmedLine[statusRange])
                        
                        devices.append(Device(name: name, udid: udid, runtime: currentRuntime, status: status))
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
