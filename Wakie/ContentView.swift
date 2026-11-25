//
//  ContentView.swift
//  Wakie
//
//  Root tab bar. The system TabView renders with Liquid Glass automatically.
//

import SwiftUI

enum AppTab: Hashable {
    case home, alarms, worldClock, settings
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: AppTab = .home

    var body: some View {
        @Bindable var model = model
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house.fill", value: .home) {
                HomeView()
            }
            Tab("Alarms", systemImage: "bell.fill", value: .alarms) {
                AlarmsView()
            }
            Tab("World Clock", systemImage: "globe", value: .worldClock) {
                WorldClockView()
            }
            Tab("Settings", systemImage: "gearshape.fill", value: .settings) {
                SettingsView()
            }
        }
        .tint(Theme.yellowDeep)
        .sensoryFeedback(.selection, trigger: selection)
        .fullScreenCover(item: $model.session) { session in
            RingingView(session: session)
        }
    }
}

#Preview {
    ContentView()
        .environment(AppModel.shared)
}
