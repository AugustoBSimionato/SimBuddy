//
//  Shell.swift
//  SimBuddy
//
//  Created by Augusto Simionato on 16/08/25.
//

import Foundation

nonisolated enum Shell {
    struct Result: Sendable {
        var exitCode: Int32
        var standardOutput: Data
        var standardError: String

        var succeeded: Bool { exitCode == 0 }

        var output: String {
            [String(decoding: standardOutput, as: UTF8.self), standardError]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }

        static let success = Result(exitCode: 0, standardOutput: Data(), standardError: "")
    }

    static func run(_ executable: String, _ arguments: [String]) async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runSynchronously(executable, arguments))
            }
        }
    }

    static func simctl(_ arguments: [String]) async -> Result {
        await run("/usr/bin/xcrun", ["simctl"] + arguments)
    }

    private static func runSynchronously(_ executable: String, _ arguments: [String]) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError

        do {
            try process.run()
        } catch {
            return Result(exitCode: -1, standardOutput: Data(), standardError: error.localizedDescription)
        }

        // Drain the pipes before waiting, otherwise a full pipe buffer deadlocks the child.
        let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return Result(
            exitCode: process.terminationStatus,
            standardOutput: outputData,
            standardError: String(decoding: errorData, as: UTF8.self)
        )
    }
}

// MARK: - simctl

nonisolated extension Shell {
    static func listSimulators() async -> Result {
        await simctl(["list", "devices", "--json"])
    }

    static func boot(udid: String) async -> Result {
        let boot = await simctl(["boot", udid])
        let alreadyBooted = boot.output.localizedCaseInsensitiveContains("current state: Booted")
        guard boot.succeeded || alreadyBooted else { return boot }

        _ = await simctl(["bootstatus", udid, "-b"])
        _ = await run("/usr/bin/open", ["-a", "Simulator", "--args", "-CurrentDeviceUDID", udid])
        return .success
    }

    static func shutdown(udid: String) async -> Result {
        await simctl(["shutdown", udid])
    }

    static func delete(udid: String) async -> Result {
        await simctl(["delete", udid])
    }

    static func diskUsage(at url: URL) async -> Int64? {
        let result = await run("/usr/bin/du", ["-sk", url.path(percentEncoded: false)])
        guard result.succeeded,
              let kilobytes = result.output.split(whereSeparator: { $0 == "\t" || $0 == " " }).first.flatMap({ Int64($0) })
        else { return nil }
        return kilobytes * 1_024
    }

    static func installedApps(udid: String, dataURL: URL?) async -> [SimulatorMetrics.App] {
        let result = await simctl(["listapps", udid])
        let simctlApps: [SimulatorMetrics.App]
        if result.succeeded,
           let object = try? PropertyListSerialization.propertyList(from: result.standardOutput, format: nil) as? [String: Any] {
            simctlApps = object.compactMap { bundleIdentifier, value in
                guard let app = value as? [String: Any] else { return nil }
                let name = (app["CFBundleDisplayName"] as? String)
                    ?? (app["CFBundleName"] as? String)
                    ?? bundleIdentifier
                let identifier = (app["CFBundleIdentifier"] as? String) ?? bundleIdentifier
                return SimulatorMetrics.App(bundleIdentifier: identifier, name: name)
            }
        } else {
            simctlApps = []
        }
        let bundleApps = dataURL.map(SimulatorFiles.installedApps(in:)) ?? []
        return Dictionary(simctlApps.map { ($0.bundleIdentifier, $0) } + bundleApps.map { ($0.bundleIdentifier, $0) }, uniquingKeysWith: { _, bundleApp in bundleApp })
            .values
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func addMedia(_ url: URL, to udid: String) async -> Result {
        await simctl(["addmedia", udid, url.path(percentEncoded: false)])
    }

    enum StatusBarTarget: Sendable {
        case allBooted
        case simulators([String])
    }

    static func overrideStatusBar(_ target: StatusBarTarget, arguments: [String]) async -> Result {
        await forEach(target) { await simctl(["status_bar", $0, "override"] + arguments) }
    }

    static func clearStatusBar(_ target: StatusBarTarget) async -> Result {
        await forEach(target) { await simctl(["status_bar", $0, "clear"]) }
    }

    private static func forEach(_ target: StatusBarTarget, _ body: (String) async -> Result) async -> Result {
        switch target {
        case .allBooted:
            return await body("booted")
        case .simulators(let udids):
            for udid in udids {
                let result = await body(udid)
                if !result.succeeded { return result }
            }
            return .success
        }
    }
}
