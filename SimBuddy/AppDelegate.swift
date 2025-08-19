//
//  AppDelegate.swift
//  SimBuddy
//
//  Created by Augusto Simionato on 16/08/25.
//

import Foundation
import AppKit

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
            "--batteryState", "discharging",
            "--batteryLevel", "100"
        ])
    }
    
    @objc private func clearOverrides() {
        _ = Shell.clearStatusBarAllBooted()
    }
    
    @objc private func openControls() {
        for w in NSApp.windows {
            if let title = w.title as String?, title.contains("Simulator Status Controls - SimBuddy") {
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
