import Foundation

public struct AgentCommand: Sendable, Equatable {
    public let executable: String
    public let arguments: [String]
    public let standardInput: Data?
    public init(executable: String = "/usr/bin/xcrun", arguments: [String], standardInput: Data? = nil) {
        self.executable = executable; self.arguments = arguments; self.standardInput = standardInput
    }
}

public struct AgentExecutionPlan: Sendable {
    public let operation: String
    public let category: AgentCategory
    public let deviceIDs: [String]
    public let commands: [AgentCommand]
    public let resultBundlePath: String?
}

public struct AgentOperationDefinition: Codable, Sendable {
    public let name: String
    public let category: AgentCategory
    public let requiredParameters: [String]
    public let optionalParameters: [String]
    public init(_ name: String, _ category: AgentCategory, _ required: [String] = [], _ optional: [String] = []) {
        self.name = name; self.category = category; requiredParameters = required; optionalParameters = optional
    }
}

public enum OperationCatalog {
    public static let definitions: [AgentOperationDefinition] = [
        .init("boot", .boot), .init("shutdown", .stop), .init("reboot", .stop),
        .init("erase", .destructive), .init("delete", .destructive),
        .init("create", .configuration, ["name", "deviceType", "runtime"]),
        .init("clone", .configuration, ["name"]), .init("rename", .configuration, ["name"]),
        .init("pair", .configuration), .init("unpair", .configuration, ["pairID"]),
        .init("pair_activate", .configuration, ["pairID"]),
        .init("listapps", .inspection), .init("appinfo", .inspection, ["bundleID"]),
        .init("get_app_container", .inspection, ["bundleID"], ["container"]),
        .init("getenv", .inspection, ["variable"]),
        .init("install", .apps, ["path"]), .init("uninstall", .apps, ["bundleID"]),
        .init("launch", .apps, ["bundleID"]), .init("terminate", .apps, ["bundleID"]),
        .init("install_app_data", .destructive, ["path"]),
        .init("addmedia", .content, ["path"]), .init("openurl", .apps, ["url"]),
        .init("pbcopy", .content, ["text"]), .init("pbpaste", .inspection),
        .init("push", .content, ["bundleID", "payload"]),
        .init("screenshot", .capture, ["path"]), .init("recordVideo", .capture, ["path"]),
        .init("location.set", .configuration, ["latitude", "longitude"]),
        .init("location.clear", .configuration),
        .init("location.list", .inspection), .init("location.run", .configuration, ["scenario"]),
        .init("location.start", .configuration, ["waypoints"], ["speed", "interval", "distance"]),
        .init("io.enumerate", .inspection), .init("io.screen.power", .configuration, ["value"]),
        .init("io.screen.geometry", .configuration, ["width", "height"], ["scale"]),
        .init("privacy.grant", .configuration, ["service", "bundleID"]),
        .init("privacy.revoke", .configuration, ["service", "bundleID"]),
        .init("privacy.reset", .configuration, ["service"], ["bundleID"]),
        .init("status_bar.clear", .configuration),
        .init("status_bar.override", .configuration, [], ["time", "batteryState", "batteryLevel", "wifiMode", "wifiBars", "cellularMode", "cellularBars", "operatorName", "dataNetwork"]),
        .init("ui.appearance.get", .inspection), .init("ui.appearance.set", .configuration, ["value"]),
        .init("ui.increase_contrast.get", .inspection), .init("ui.increase_contrast.set", .configuration, ["value"]),
        .init("ui.content_size.get", .inspection), .init("ui.content_size.set", .configuration, ["value"]),
        .init("keychain.reset", .destructive), .init("keychain.add-root-cert", .configuration, ["path"]),
        .init("keychain.add-cert", .configuration, ["path"]), .init("icloud_sync", .content),
        .init("logverbose", .configuration, ["value"]),
        .init("test", .tests, ["projectPath", "scheme"], ["action", "onlyTesting", "skipTesting"])
    ]

    public static func plan(_ input: AgentOperationInput, inventory: AgentInventory,
                            resultBundlePath: String? = nil) throws -> AgentExecutionPlan {
        guard let definition = definitions.first(where: { $0.name == input.operation }) else {
            throw AgentFailure("Unsupported operation. Use describe_operations for the classified catalog.")
        }
        let p = input.parameters
        let allowed = Set(definition.requiredParameters + definition.optionalParameters)
        guard Set(p.keys).isSubset(of: allowed),
              p.values.allSatisfy({ !$0.contains("\0") && $0.utf8.count <= 1_048_576 }) else {
            throw AgentFailure("Unknown parameter or invalid value.")
        }
        for key in definition.requiredParameters where p[key]?.isEmpty != false {
            throw AgentFailure("Missing parameter: \(key).")
        }
        func value(_ key: String) throws -> String {
            guard let value = p[key], !value.isEmpty, !value.hasPrefix("-") else {
                throw AgentFailure("Invalid parameter: \(key).")
            }
            return value
        }
        func path(_ key: String) throws -> String {
            let path = try value(key)
            guard path.hasPrefix("/") else { throw AgentFailure("\(key) must be an absolute path.") }
            return path
        }
        func choice(_ key: String, _ options: [String]) throws -> String {
            let result = try value(key)
            guard options.contains(result) else { throw AgentFailure("Invalid \(key): expected \(options.joined(separator: ", ")).") }
            return result
        }
        let available = Set(inventory.devices.map(\.id))
        var ids = Set<String>()
        for target in input.devices {
            switch target {
            case "all": ids.formUnion(available)
            case "booted": ids.formUnion(inventory.devices.filter { $0.state == "Booted" }.map(\.id))
            default:
                guard UUID(uuidString: target) != nil, available.contains(target) else { throw AgentFailure("Unknown simulator UDID: \(target).") }
                ids.insert(target)
            }
        }
        if ["unpair", "pair_activate"].contains(input.operation) {
            let pairID = try value("pairID")
            guard input.devices.isEmpty, let pair = inventory.pairs[pairID], available.isSuperset(of: [pair.watch, pair.phone]) else {
                throw AgentFailure("Unknown pair, unavailable peer, or unexpected devices.")
            }
            ids.formUnion([pair.watch, pair.phone])
        }
        if input.operation == "create" {
            guard input.devices.isEmpty else { throw AgentFailure("create does not accept existing devices.") }
        } else {
            guard !ids.isEmpty else { throw AgentFailure("At least one available simulator is required.") }
        }
        if ["clone", "rename", "test", "recordVideo"].contains(input.operation), ids.count != 1 {
            throw AgentFailure("This operation requires exactly one simulator.")
        }
        if input.operation == "pair", ids.count != 2 { throw AgentFailure("pair requires a watch and a phone UDID, in that order.") }
        if ["screenshot", "recordVideo"].contains(input.operation), ids.count != 1 {
            throw AgentFailure("Captures require one simulator and an explicit output path.")
        }
        let related = inventory.relatedIDs(ids).sorted()
        guard available.isSuperset(of: related) else { throw AgentFailure("A paired simulator is unavailable.") }
        var commands: [AgentCommand] = []
        var bundle: String?
        if input.operation == "test" {
            let project = try path("projectPath")
            let suffix = URL(fileURLWithPath: project).pathExtension
            guard ["xcodeproj", "xcworkspace"].contains(suffix), let resultBundlePath else { throw AgentFailure("An Xcode project/workspace and result path are required.") }
            let action = try p["action"].map { _ in try choice("action", ["test", "test-without-building"]) } ?? "test"
            var args = ["xcodebuild", action, suffix == "xcworkspace" ? "-workspace" : "-project", project,
                        "-scheme", try value("scheme"), "-destination", "id=\(ids.sorted()[0])",
                        "-parallel-testing-enabled", "NO", "-maximum-concurrent-test-simulator-destinations", "1",
                        "-resultBundlePath", resultBundlePath]
            for (key, flag) in [("onlyTesting", "-only-testing:"), ("skipTesting", "-skip-testing:")] {
                if let filters = p[key] {
                    for filter in filters.split(separator: ",").map(String.init) {
                        guard !filter.isEmpty, !filter.contains("\n"), !filter.hasPrefix("-") else { throw AgentFailure("Invalid test filter.") }
                        args.append(flag + filter)
                    }
                }
            }
            commands = [.init(arguments: args)]
            bundle = resultBundlePath
        } else if input.operation == "create" {
            let runtime = try value("runtime"), deviceType = try value("deviceType")
            guard runtime.hasPrefix("com.apple.CoreSimulator.SimRuntime."), deviceType.hasPrefix("com.apple.CoreSimulator.SimDeviceType.") else {
                throw AgentFailure("Use complete runtime and device type identifiers.")
            }
            commands = [.init(arguments: ["simctl", "create", try value("name"), deviceType, runtime])]
        } else if input.operation == "pair" {
            guard input.devices.count == 2, ids.count == 2,
                  inventory.devices.first(where: { $0.id == input.devices[0] })?.runtime.contains("watchOS") == true,
                  inventory.devices.first(where: { $0.id == input.devices[1] })?.runtime.contains("iOS") == true else {
                throw AgentFailure("pair requires explicit watch and phone UDIDs, in that order.")
            }
            commands = [.init(arguments: ["simctl", "pair"] + input.devices)]
        } else if ["unpair", "pair_activate"].contains(input.operation) {
            commands = [.init(arguments: ["simctl", input.operation, try value("pairID")])]
        } else {
            for id in ids.sorted() {
                var args = [input.operation, id]
                var stdin: Data?
                switch input.operation {
                case "boot", "shutdown", "reboot", "erase", "delete", "listapps", "pbpaste", "icloud_sync": break
                case "clone", "rename": args.append(try value("name"))
                case "install", "addmedia": args.append(try path("path"))
                case "uninstall", "launch", "terminate", "appinfo": args.append(try value("bundleID"))
                case "get_app_container": args += [try value("bundleID"), try p["container"].map { _ in try choice("container", ["app", "data", "groups"]) } ?? "app"]
                case "getenv": args.append(try value("variable"))
                case "install_app_data": args.append(try path("path"))
                case "openurl":
                    let url = try value("url")
                    guard URL(string: url)?.scheme != nil else { throw AgentFailure("An absolute URL is required.") }
                    args.append(url)
                case "pbcopy": stdin = Data(p["text", default: ""].utf8)
                case "push":
                    let payload = Data(p["payload", default: ""].utf8)
                    guard (try? JSONSerialization.jsonObject(with: payload)) is [String: Any] else { throw AgentFailure("Push payload must be a JSON object.") }
                    args += [try value("bundleID"), "-"]; stdin = payload
                case "screenshot": args = ["io", id, "screenshot", "--type=png", try path("path")]
                case "recordVideo": args = ["io", id, "recordVideo", "--codec=h264", try path("path")]
                case "location.set":
                    guard let lat = Double(p["latitude", default: ""]), let lon = Double(p["longitude", default: ""]),
                          lat.isFinite, lon.isFinite, (-90...90).contains(lat), (-180...180).contains(lon) else { throw AgentFailure("Invalid coordinates.") }
                    args = ["location", id, "set", "\(lat),\(lon)"]
                case "location.clear", "location.list": args = ["location", id, String(input.operation.split(separator: ".")[1])]
                case "location.run": args = ["location", id, "run", try value("scenario")]
                case "location.start":
                    let points = p["waypoints", default: ""].split(whereSeparator: \.isWhitespace).map(String.init)
                    guard points.count >= 2, points.allSatisfy({ point in
                        let components = point.split(separator: ",")
                        guard components.count == 2, let lat = Double(components[0]), let lon = Double(components[1]) else { return false }
                        return lat.isFinite && lon.isFinite && (-90...90).contains(lat) && (-180...180).contains(lon)
                    }), p["distance"] == nil || p["interval"] == nil else { throw AgentFailure("Use at least two space-separated latitude,longitude waypoints and either distance or interval.") }
                    args = ["location", id, "start"]
                    for key in ["speed", "distance", "interval"] {
                        if let raw = p[key] {
                            guard let number = Double(raw), number.isFinite, number > 0 else { throw AgentFailure("Invalid location interval, distance or speed.") }
                            args.append("--\(key)=\(number)")
                        }
                    }
                    args += points
                case "io.enumerate": args = ["io", id, "enumerate"]
                case "io.screen.power": args = ["io", id, "screenConfig", "power", try choice("value", ["on", "off"])]
                case "io.screen.geometry":
                    guard let width = Int(p["width", default: ""]), let height = Int(p["height", default: ""]),
                          width > 0, height > 0, width <= 16_384, height <= 16_384 else { throw AgentFailure("Invalid screen dimensions.") }
                    var geometry = "\(width)x\(height)"
                    if let scale = p["scale"] {
                        guard let number = Double(scale), number.isFinite, number > 0, number <= 8 else { throw AgentFailure("Invalid screen scale.") }
                        geometry += "@\(number)"
                    }
                    args = ["io", id, "screenConfig", "geometry", geometry]
                case "privacy.grant", "privacy.revoke", "privacy.reset":
                    let action = String(input.operation.split(separator: ".")[1])
                    let service = try choice("service", ["all", "calendar", "contacts-limited", "contacts", "location", "location-always", "photos-add", "photos", "media-library", "microphone", "motion", "reminders", "siri"])
                    args = ["privacy", id, action, service]
                    if p["bundleID"] != nil { args.append(try value("bundleID")) }
                case "status_bar.clear": args = ["status_bar", id, "clear"]
                case "status_bar.override":
                    guard !p.isEmpty else { throw AgentFailure("At least one status bar override is required.") }
                    args = ["status_bar", id, "override"]
                    let flags = ["time": "time", "batteryState": "batteryState", "batteryLevel": "batteryLevel", "wifiMode": "wifiMode", "wifiBars": "wifiBars", "cellularMode": "cellularMode", "cellularBars": "cellularBars", "operatorName": "operatorName", "dataNetwork": "dataNetwork"]
                    for key in p.keys.sorted() { args += ["--" + flags[key]!, try value(key)] }
                case let op where op.hasPrefix("ui."):
                    let parts = op.split(separator: ".").map(String.init)
                    args = ["ui", id, parts[1]]
                    if parts[2] == "set" {
                        let choices = parts[1] == "appearance" ? ["light", "dark"] : parts[1] == "increase_contrast" ? ["enabled", "disabled"] : ["extra-small", "small", "medium", "large", "extra-large", "extra-extra-large", "extra-extra-extra-large", "accessibility-medium", "accessibility-large", "accessibility-extra-large", "accessibility-extra-extra-large", "accessibility-extra-extra-extra-large"]
                        args.append(try choice("value", choices))
                    }
                case "keychain.reset": args = ["keychain", id, "reset"]
                case "keychain.add-root-cert", "keychain.add-cert": args = ["keychain", id, String(input.operation.split(separator: ".")[1]), try path("path")]
                case "logverbose": args = ["logverbose", id, try choice("value", ["enable", "disable"])]
                default: throw AgentFailure("Unclassified operation.")
                }
                commands.append(.init(arguments: ["simctl"] + args, standardInput: stdin))
                if input.operation == "boot" || input.operation == "reboot" {
                    commands.append(.init(arguments: ["simctl", "bootstatus", id, "-b"]))
                }
            }
        }
        return AgentExecutionPlan(operation: input.operation, category: definition.category, deviceIDs: related,
                                  commands: commands, resultBundlePath: bundle)
    }
}
