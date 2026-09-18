//
//  Simulator.swift
//  SimBuddy
//
//  Created by Augusto Simionato on 16/08/25.
//

import Foundation

nonisolated struct Simulator: Identifiable, Hashable, Sendable {
    enum State: Hashable, Sendable {
        case booted
        case booting
        case shutdown
        case shuttingDown
        case other(String)

        init(_ rawValue: String) {
            switch rawValue {
            case "Booted": self = .booted
            case "Booting": self = .booting
            case "Shutdown": self = .shutdown
            case "Shutting Down": self = .shuttingDown
            default: self = .other(rawValue)
            }
        }
    }

    let udid: String
    let name: String
    let runtime: Runtime
    let deviceType: String
    let dataURL: URL?
    var state: State

    var id: String { udid }
    var isBooted: Bool { state == .booted }
    var supportsFileSharing: Bool { runtime.platform == "iOS" || runtime.platform == "visionOS" }

    var deviceTypeName: String {
        deviceType
            .split(separator: ".")
            .last
            .map { String($0).replacing("-", with: " ") } ?? name
    }

    var stateName: String {
        switch state {
        case .booted: "Em execução"
        case .booting: "Iniciando"
        case .shutdown: "Desligado"
        case .shuttingDown: "Encerrando"
        case .other(let value): value
        }
    }

    var symbolName: String {
        switch family {
        case .iPhone: "iphone"
        case .iPad: "ipad"
        case .watch: "applewatch"
        case .tv: "appletv"
        case .vision: "vision.pro"
        case .other: "square.dashed"
        }
    }

    fileprivate enum Family: Int, Comparable {
        case iPhone, iPad, watch, tv, vision, other

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    fileprivate var family: Family {
        let identifier = deviceType.isEmpty ? name : deviceType
        if identifier.localizedCaseInsensitiveContains("iPhone") { return .iPhone }
        if identifier.localizedCaseInsensitiveContains("iPad") { return .iPad }
        if identifier.localizedCaseInsensitiveContains("Watch") { return .watch }
        if identifier.localizedCaseInsensitiveContains("TV") { return .tv }
        if identifier.localizedCaseInsensitiveContains("Vision") { return .vision }
        return .other
    }
}

nonisolated struct SimulatorMetrics: Hashable, Sendable {
    struct App: Hashable, Identifiable, Sendable {
        let bundleIdentifier: String
        let name: String

        var id: String { bundleIdentifier }
    }

    let diskUsage: Int64?
    let apps: [App]
}

nonisolated struct Runtime: Hashable, Comparable, Sendable {
    let identifier: String
    let platform: String
    let version: String

    var name: String { "\(platform) \(version)" }

    init(identifier: String) {
        self.identifier = identifier

        // com.apple.CoreSimulator.SimRuntime.iOS-26-0 → ("iOS", "26.0")
        let components = identifier.split(separator: ".").last.map { $0.split(separator: "-") } ?? []
        let rawPlatform = components.first.map(String.init) ?? identifier
        platform = rawPlatform == "xrOS" ? "visionOS" : rawPlatform
        version = components.dropFirst().joined(separator: ".")
    }

    private var platformOrder: Int {
        ["iOS", "watchOS", "tvOS", "visionOS"].firstIndex(of: platform) ?? .max
    }

    static func < (lhs: Runtime, rhs: Runtime) -> Bool {
        if lhs.platformOrder != rhs.platformOrder { return lhs.platformOrder < rhs.platformOrder }
        return lhs.version.compare(rhs.version, options: .numeric) == .orderedDescending
    }
}

nonisolated enum SimulatorList {
    private struct Response: Decodable {
        let devices: [String: [Entry]]
    }

    private struct Entry: Decodable {
        let udid: String
        let name: String
        let state: String
        let isAvailable: Bool?
        let deviceTypeIdentifier: String?
        let dataPath: String?
    }

    static func decode(_ data: Data) throws -> [Simulator] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.devices
            .flatMap { identifier, entries in
                let runtime = Runtime(identifier: identifier)
                return entries
                    .filter { $0.isAvailable ?? true }
                    .map {
                        Simulator(
                            udid: $0.udid,
                            name: $0.name,
                            runtime: runtime,
                            deviceType: $0.deviceTypeIdentifier ?? "",
                            dataURL: $0.dataPath.map { URL(filePath: $0, directoryHint: .isDirectory) },
                            state: .init($0.state)
                        )
                    }
            }
            .sorted {
                if $0.runtime != $1.runtime { return $0.runtime < $1.runtime }
                if $0.family != $1.family { return $0.family < $1.family }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }
}
