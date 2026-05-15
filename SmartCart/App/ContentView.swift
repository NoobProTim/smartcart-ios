// ContentView.swift — SmartCart/App/ContentView.swift
//
// Root tab container. Three tabs: Home, Flyers, Settings.
// Alerts and History tabs removed. Receipt scanner is dormant (commented out in HomeView).

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }
            FlyersView()
                .tabItem {
                    Label("Flyers", systemImage: "tag")
                }
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}
