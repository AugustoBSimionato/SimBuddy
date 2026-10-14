//
//  AppDelegate.swift
//  SimBuddy
//
//  Created by Augusto Simionato on 16/08/25.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = SimulatorViewModel()
    private var menuTrackingObserver: (any NSObjectProtocol)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        viewModel.startMonitoring()
        menuTrackingObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let menu = notification.object as? NSMenu,
                      menu.item(withTitle: String(localized: "Monitoramento de agentes")) != nil else { return }
                Task { await self.viewModel.refresh() }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let menuTrackingObserver { NotificationCenter.default.removeObserver(menuTrackingObserver) }
        viewModel.stopMonitoring()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        viewModel.agentMonitor.refreshNotificationAuthorization()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
