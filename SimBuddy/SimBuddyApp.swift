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
        WindowGroup("Simulator Status Controls") {
            ControlsView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 600, height: 520)
    }
}
