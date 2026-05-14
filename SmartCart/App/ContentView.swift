// ContentView.swift — SmartCart/App/ContentView.swift
//
// Root tab container. Three tabs: Smart List, Scan Receipt, Settings.

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Smart List", systemImage: "cart")
                }
            MultiShotCaptureView()
                .tabItem {
                    Label("Scan", systemImage: "camera")
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
