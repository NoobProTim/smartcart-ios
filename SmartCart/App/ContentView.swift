// ContentView.swift — SmartCart/App/ContentView.swift
//
// Root tab container. Four tabs: Home, Flyers, My List, Settings.
// GroceryListViewModel lives here and is injected as an environment object
// so the tab badge and the list view share a single source of truth.

import SwiftUI

struct ContentView: View {
    @StateObject private var cartVM = GroceryListViewModel()
    @State private var selectedTab = 1  // Flyers until they have list items

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)

            FlyersView()
                .tabItem { Label("Flyers", systemImage: "tag") }
                .tag(1)

            NavigationStack {
                GroceryListView()
            }
            .tabItem { Label("My List", systemImage: "cart.fill") }
            .badge(cartVM.items.count > 0 ? cartVM.items.count : 0)
            .tag(2)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(3)
        }
        .environmentObject(cartVM)
        .onAppear {
            cartVM.load()
            // Return users with items go to Home; new users stay on Flyers.
            if !cartVM.items.isEmpty { selectedTab = 0 }
        }
    }
}
