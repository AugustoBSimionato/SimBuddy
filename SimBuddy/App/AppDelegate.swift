//
//  AppDelegate.swift
//  SimBuddy
//
//  Created by Augusto Simionato on 16/08/25.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = SimulatorViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        viewModel.startMonitoring()

    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.stopMonitoring()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        viewModel.agentMonitor.refreshNotificationAuthorization()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
