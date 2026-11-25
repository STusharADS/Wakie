//
//  WakieApp.swift
//  Wakie
//
//  Created by Tushar Shaw on 16/11/2026.
//

import AppIntents
import SwiftUI

@main
struct WakieApp: App {
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .task {
                    model.start()
                    // Refresh the alarms and World Clock cities Siri phrases can mention.
                    WakieShortcuts.updateAppShortcutParameters()
                }
        }
    }
}
