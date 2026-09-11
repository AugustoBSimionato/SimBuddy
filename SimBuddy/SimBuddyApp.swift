//
//  SimBuddyApp.swift
//  SimBuddy
//
//  Created by Augusto Simionato on 16/08/25.
//

import SwiftUI

@main
struct SimBuddyApp: App {
    static let mainWindowID = "main"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = SimulatorStore()

    var body: some Scene {
        Window("SimBuddy", id: Self.mainWindowID) {
            ContentView()
                .environment(store)
        }
        .defaultSize(width: 980, height: 700)
        .commands {
            SimulatorCommands(store: store)
        }

        Settings {
            SettingsView()
        }

        MenuBarExtra("SimBuddy", systemImage: "platter.filled.top.iphone") {
            MenuBarContent()
                .environment(store)
        }
    }
}
