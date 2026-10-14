import Foundation

public struct AgentSavedState: Codable, Sendable {
    public var settings: AgentSettings
    public var events: [AgentEvent]
    public init(settings: AgentSettings = AgentSettings(), events: [AgentEvent] = []) {
        self.settings = settings; self.events = events
    }
}

public final class AgentPersistence: Sendable {
    public let directory: URL
    public init(directory: URL = URL.applicationSupportDirectory.appending(path: "SimBuddy/Agents", directoryHint: .isDirectory)) {
        self.directory = directory
    }
    public func load() throws -> AgentSavedState {
        let url = directory.appending(path: "state.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return AgentSavedState() }
        return try JSONDecoder().decode(AgentSavedState.self, from: Data(contentsOf: url))
    }
    public func save(_ state: AgentSavedState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var bounded = state
        bounded.events = Array(state.events.suffix(5_000))
        let url = directory.appending(path: "state.json")
        try JSONEncoder().encode(bounded).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
