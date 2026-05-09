// ContentView.swift — SmartCart/App/ContentView.swift
//
// Root tab container. Three tabs: Smart List, Scan Receipt, Settings.

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            SmartListView()
                .tabItem {
                    Label("Smart List", systemImage: "cart")
                }
            ReceiptScanView()
                .tabItem {
                    Label("Scan", systemImage: "camera")
                }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}
