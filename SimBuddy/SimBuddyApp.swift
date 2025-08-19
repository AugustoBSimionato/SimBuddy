//
//  SimBuddyApp.swift
//  SimBuddy
//
//  Created by Augusto Simionato on 16/08/25.
//

import SwiftUI

@main
struct SimStatusBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("Simulator Status Controls - SimBuddy") {
            ControlsView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 720, height: 920)
    }
}
