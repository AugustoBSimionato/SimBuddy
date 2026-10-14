import Foundation

public enum AgentCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case inspection, boot, stop, destructive, apps, tests, capture, configuration, content
    public var id: String { rawValue }
}

public struct AgentProtection: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var blocked: Set<AgentCategory>

    public init(enabled: Bool = false, blocked: Set<AgentCategory> = [.stop, .destructive]) {
        self.enabled = enabled
        self.blocked = blocked
    }

    public func permits(_ category: AgentCategory) -> Bool { !enabled || !blocked.contains(category) }
}

public enum AgentOutcome: String, Codable, CaseIterable, Sendable, Identifiable {
    case requested, queued, started, succeeded, failed, blocked, cancelled, interrupted, observed
    public var id: String { rawValue }
    public var isTerminal: Bool { ![.requested, .queued, .started].contains(self) }
}

public struct AgentEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let operationID: UUID?
    public let sessionID: UUID?
    public let clientName: String?
    public let deviceIDs: [String]
    public let deviceNames: [String]
    public let operation: String
    public let category: AgentCategory
    public let outcome: AgentOutcome
    public let detail: String?

    public init(operationID: UUID? = nil, sessionID: UUID? = nil, clientName: String? = nil,
                deviceIDs: [String], deviceNames: [String], operation: String,
                category: AgentCategory, outcome: AgentOutcome, detail: String? = nil) {
        id = UUID()
        date = Date()
        self.operationID = operationID
        self.sessionID = sessionID
        self.clientName = clientName
        self.deviceIDs = deviceIDs
        self.deviceNames = deviceNames
        self.operation = operation
        self.category = category
        self.outcome = outcome
        self.detail = detail
    }
}

public struct AgentSettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var protections: [String: AgentProtection] = [:]
    public var mutedCategories: Set<AgentCategory> = []
    public init() {}
}

public struct AgentOperationInput: Codable, Equatable, Sendable {
    public var operation: String
    public var devices: [String]
    public var parameters: [String: String]
    public init(operation: String, devices: [String] = [], parameters: [String: String] = [:]) {
        self.operation = operation
        self.devices = devices
        self.parameters = parameters
    }
}

public struct AgentBridgeRequest: Codable, Sendable {
    public var method: String
    public var sessionID: UUID
    public var clientName: String
    public var input: AgentOperationInput?
    public var operationID: UUID?
    public init(method: String, sessionID: UUID, clientName: String,
                input: AgentOperationInput? = nil, operationID: UUID? = nil) {
        self.method = method
        self.sessionID = sessionID
        self.clientName = String(clientName.prefix(120))
        self.input = input
        self.operationID = operationID
    }
}

public struct AgentBridgeResponse: Codable, Sendable {
    public var text: String
    public var isError: Bool
    public init(_ text: String, isError: Bool = false) { self.text = text; self.isError = isError }
    public static func encoded<T: Encodable>(_ value: T) throws -> Self {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return Self(String(decoding: try encoder.encode(value), as: UTF8.self))
    }
}

public struct AgentDevice: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let state: String
    public let runtime: String
    public init(id: String, name: String, state: String, runtime: String) {
        self.id = id; self.name = name; self.state = state; self.runtime = runtime
    }
}

public struct AgentPair: Codable, Equatable, Sendable {
    public let watch: String
    public let phone: String
    public init(watch: String, phone: String) { self.watch = watch; self.phone = phone }
}

public struct AgentInventory: Equatable, Sendable {
    public var devices: [AgentDevice]
    public var pairs: [String: AgentPair]
    public init(devices: [AgentDevice], pairs: [String: AgentPair] = [:]) {
        self.devices = devices; self.pairs = pairs
    }

    public static func decode(_ data: Data) throws -> Self {
        struct Entry: Decodable { let udid: String; let name: String; let state: String; let isAvailable: Bool? }
        struct Peer: Decodable { let udid: String }
        struct PairEntry: Decodable { let watch: Peer; let phone: Peer }
        struct Response: Decodable { let devices: [String: [Entry]]; let pairs: [String: PairEntry]? }
        let result = try JSONDecoder().decode(Response.self, from: data)
        return Self(devices: result.devices.flatMap { runtime, entries in
            entries.filter { $0.isAvailable ?? true }.map { AgentDevice(id: $0.udid, name: $0.name, state: $0.state, runtime: runtime) }
        }.sorted { $0.id < $1.id }, pairs: (result.pairs ?? [:]).mapValues { AgentPair(watch: $0.watch.udid, phone: $0.phone.udid) })
    }

    public func relatedIDs(_ ids: Set<String>) -> Set<String> {
        var related = ids
        for pair in pairs.values where ids.contains(pair.watch) || ids.contains(pair.phone) {
            related.formUnion([pair.watch, pair.phone])
        }
        return related
    }
}

public struct AgentFailure: LocalizedError, Sendable {
    public enum Code: String, Sendable { case invalidInput, disabled, protectedDevice, unavailable }
    public let message: String
    public let code: Code
    public init(_ message: String, code: Code = .invalidInput) { self.message = message; self.code = code }
    public var errorDescription: String? { message }
}

public enum AgentPolicy {
    public static func check(category: AgentCategory, deviceIDs: [String], settings: AgentSettings) throws {
        guard settings.enabled else { throw AgentFailure("Agent monitoring is disabled in SimBuddy.", code: .disabled) }
        let denied = deviceIDs.filter { !(settings.protections[$0] ?? AgentProtection()).permits(category) }
        guard denied.isEmpty else { throw AgentFailure("Blocked by simulator protection: \(category.rawValue) (\(denied.joined(separator: ", "))).", code: .protectedDevice) }
    }
}

public struct AgentSnapshotTracker: Sendable {
    private var previous: [String: AgentDevice]?
    public init() {}
    public mutating func reset() { previous = nil }
    public mutating func observe(_ devices: [AgentDevice], suppressed: Set<String> = []) -> [AgentEvent] {
        let current = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0) })
        defer { previous = current }
        guard let previous else { return [] }
        return Set(previous.keys).union(current.keys).sorted().compactMap { id in
            guard !suppressed.contains(id) else { return nil }
            let old = previous[id], new = current[id]
            guard old?.state != new?.state || old == nil || new == nil else { return nil }
            let device = new ?? old!
            let operation = old == nil ? "available" : new == nil ? "unavailable" : "state"
            return AgentEvent(deviceIDs: [id], deviceNames: [device.name], operation: operation,
                              category: .configuration, outcome: .observed, detail: new?.state)
        }
    }
}
